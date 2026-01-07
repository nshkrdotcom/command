defmodule Command.Pipelines do
  @moduledoc """
  Pipeline orchestration context integrating FlowStone.

  ## Examples

      {:ok, template} =
        Command.Pipelines.create_template(%{
          name: "Daily Summary",
          config: %{module: "MyApp.Pipelines.Summary", final_asset: :report}
        })

      {:ok, execution} = Command.Pipelines.run(template, "2026-01-05")
  """

  require Logger

  import Ecto.Query

  alias Command.Pipelines.{AIOperation, Execution, Template}
  alias Command.Repo
  alias Command.Workflows.Workflow

  @doc """
  Creates a pipeline template from a workflow template.
  """
  @spec create_template(Workflow.t(), map()) :: {:ok, Template.t()} | {:error, Ecto.Changeset.t()}
  def create_template(%Workflow{} = workflow, attrs) when is_map(attrs) do
    attrs = Map.put(attrs, :template_id, workflow.id)

    %Template{}
    |> Template.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a pipeline template using raw attributes.
  """
  @spec create_template(map()) :: {:ok, Template.t()} | {:error, Ecto.Changeset.t()}
  def create_template(attrs) when is_map(attrs) do
    %Template{}
    |> Template.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists pipeline templates.
  """
  @spec list_templates(keyword()) :: [Template.t()]
  def list_templates(opts \\ []) do
    Template
    |> apply_template_filters(opts)
    |> order_by([t], desc: t.updated_at)
    |> Repo.all()
  end

  @doc """
  Gets a pipeline template by ID.
  """
  @spec get_template!(Ecto.UUID.t()) :: Template.t()
  def get_template!(id), do: Repo.get!(Template, id)

  @doc """
  Creates a pipeline execution record.
  """
  @spec create_execution(Template.t(), String.t(), keyword()) ::
          {:ok, Execution.t()} | {:error, Ecto.Changeset.t()}
  def create_execution(%Template{} = template, partition, opts \\ []) do
    attrs = %{
      pipeline_id: template.id,
      partition: partition,
      flowstone_run_id: Keyword.get_lazy(opts, :flowstone_run_id, &Ecto.UUID.generate/0),
      session_id: opts[:session_id],
      user_id: opts[:user_id]
    }

    %Execution{}
    |> Execution.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Runs a pipeline template and records the execution.
  """
  @spec run(Ecto.UUID.t() | Template.t(), String.t(), keyword()) ::
          {:ok, Execution.t()} | {:error, term()}
  def run(template_or_id, partition, opts \\ []) do
    template = resolve_template(template_or_id)

    with {:ok, execution} <- create_execution(template, partition, opts),
         {:ok, execution} <- mark_running(execution),
         {:ok, pipeline_module} <- resolve_pipeline_module(template, opts),
         {:ok, asset_name} <- resolve_final_asset(template, opts) do
      run_flowstone(pipeline_module, asset_name, execution, opts)
    else
      {:error, _} = error -> error
    end
  end

  @doc """
  Gets a pipeline execution by ID.
  """
  @spec get_execution!(Ecto.UUID.t()) :: Execution.t()
  def get_execution!(id), do: Repo.get!(Execution, id)

  @doc """
  Lists executions for a pipeline template.
  """
  @spec list_executions(Template.t(), keyword()) :: [Execution.t()]
  def list_executions(%Template{} = template, opts \\ []) do
    Execution
    |> where([e], e.pipeline_id == ^template.id)
    |> apply_execution_filters(opts)
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
  end

  @doc """
  Records an AI operation for a pipeline execution.
  """
  @spec record_ai_operation(map()) :: {:ok, AIOperation.t()} | {:error, Ecto.Changeset.t()}
  def record_ai_operation(attrs) when is_map(attrs) do
    %AIOperation{}
    |> AIOperation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists AI operations for a pipeline execution.
  """
  @spec list_ai_operations(Ecto.UUID.t()) :: [AIOperation.t()]
  def list_ai_operations(execution_id) do
    AIOperation
    |> where([o], o.pipeline_run_id == ^execution_id)
    |> order_by([o], desc: o.inserted_at)
    |> Repo.all()
  end

  defp resolve_template(%Template{} = template), do: template
  defp resolve_template(template_id), do: get_template!(template_id)

  defp mark_running(%Execution{} = execution) do
    execution
    |> Execution.changeset(%{status: :running, started_at: DateTime.utc_now()})
    |> Repo.update()
  end

  defp mark_completed(%Execution{} = execution, result) do
    execution
    |> Execution.changeset(%{
      status: :completed,
      completed_at: DateTime.utc_now(),
      result: normalize_result(result)
    })
    |> Repo.update()
  end

  defp mark_failed(%Execution{} = execution, error) do
    execution
    |> Execution.changeset(%{
      status: :failed,
      completed_at: DateTime.utc_now(),
      error: normalize_error(error)
    })
    |> Repo.update()
  end

  defp run_flowstone(pipeline_module, asset_name, execution, opts) do
    resources = build_resources(execution, opts)

    {resource_server, restore_env} = maybe_start_resources(resources)
    telemetry_handler = attach_ai_telemetry(execution)

    run_opts =
      [
        partition: execution.partition,
        force: Keyword.get(opts, :force, false),
        with_deps: Keyword.get(opts, :with_deps, true)
      ]
      |> maybe_put(:run_id, execution.flowstone_run_id)

    try do
      case FlowStone.run(pipeline_module, asset_name, run_opts) do
        {:ok, result} ->
          case mark_completed(execution, result) do
            {:ok, updated} -> {:ok, updated}
            {:error, changeset} -> {:error, changeset}
          end

        {:error, reason} ->
          case mark_failed(execution, reason) do
            {:ok, updated} -> {:error, updated}
            {:error, changeset} -> {:error, changeset}
          end
      end
    after
      detach_ai_telemetry(telemetry_handler)
      restore_env.()
      maybe_stop_resources(resource_server)
    end
  end

  defp build_resources(execution, opts) do
    base = %{}
    base = maybe_add_command_context(base, execution, opts)
    base = maybe_add_ai_resource(base, execution, opts)

    case Keyword.get(opts, :resources) do
      nil -> base
      resources when is_map(resources) -> Map.merge(base, resources)
    end
  end

  defp maybe_add_command_context(resources, execution, opts) do
    if Keyword.get(opts, :command_context, true) do
      config = %{
        run_id: execution.id,
        session_id: execution.session_id,
        user_id: execution.user_id
      }

      Map.put(resources, :command_context, {Command.Pipelines.Resources.CommandContext, config})
    else
      resources
    end
  end

  defp maybe_add_ai_resource(resources, %Execution{} = execution, opts) do
    if Keyword.get(opts, :ai_enabled, true) do
      adapter = Keyword.get(opts, :ai_adapter, Altar.AI.Adapters.Composite)
      adapter_opts = Keyword.get(opts, :ai_adapter_opts, [])

      telemetry_metadata =
        opts
        |> Keyword.get(:ai_telemetry_metadata, %{})
        |> Map.merge(command_metadata_for_ai(execution, opts))

      config = %{
        adapter: adapter,
        adapter_opts: adapter_opts,
        telemetry_metadata: telemetry_metadata
      }

      Map.put(resources, :ai, {Altar.AI.Integrations.FlowStone, config})
    else
      resources
    end
  end

  defp maybe_start_resources(resources) when map_size(resources) == 0 do
    {nil, fn -> :ok end}
  end

  defp maybe_start_resources(resources) do
    case Process.whereis(FlowStone.Resources) do
      nil ->
        previous = Application.get_env(:flowstone, :resources_server, FlowStone.Resources)

        {:ok, resource_server} =
          FlowStone.Resources.start_link(resources: resources, name: FlowStone.Resources)

        Application.put_env(:flowstone, :resources_server, resource_server)

        restore_env = fn ->
          Application.put_env(:flowstone, :resources_server, previous)
        end

        {resource_server, restore_env}

      _pid ->
        {nil, fn -> :ok end}
    end
  end

  defp maybe_stop_resources(nil), do: :ok

  defp maybe_stop_resources(resource_server) do
    if Process.alive?(resource_server) do
      GenServer.stop(resource_server)
    end

    :ok
  end

  defp resolve_pipeline_module(%Template{} = template, opts) do
    module =
      Keyword.get(opts, :module) ||
        Map.get(template.config, :module) ||
        Map.get(template.config, "module")

    case normalize_module(module) do
      {:ok, mod} ->
        if Code.ensure_loaded?(mod) do
          {:ok, mod}
        else
          {:error, {:module_not_loaded, mod}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_module(nil), do: {:error, :missing_pipeline_module}
  defp normalize_module(module) when is_atom(module), do: {:ok, module}

  defp normalize_module(module) when is_binary(module) do
    module =
      module
      |> String.trim()
      |> String.trim_leading("Elixir.")

    {:ok, Module.concat([module])}
  end

  defp resolve_final_asset(%Template{} = template, opts) do
    asset =
      Keyword.get(opts, :asset) ||
        Map.get(template.config, :final_asset) ||
        Map.get(template.config, "final_asset") ||
        :output

    case normalize_asset(asset) do
      {:ok, name} -> {:ok, name}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_asset(asset) when is_atom(asset), do: {:ok, asset}
  defp normalize_asset(asset) when is_binary(asset), do: {:ok, String.to_atom(asset)}
  defp normalize_asset(_), do: {:error, :invalid_asset}

  defp normalize_result(result) when is_map(result), do: result
  defp normalize_result(result), do: %{output: result}

  defp normalize_error(%FlowStone.Error{} = error) do
    %{type: error.type, message: error.message, details: Map.from_struct(error)}
  end

  defp normalize_error(error) do
    %{type: :error, message: inspect(error)}
  end

  defp apply_template_filters(query, opts) do
    query
    |> maybe_filter_status(opts[:status])
    |> maybe_filter_template(opts[:template_id])
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [t], t.status == ^status)

  defp maybe_filter_template(query, nil), do: query

  defp maybe_filter_template(query, template_id),
    do: where(query, [t], t.template_id == ^template_id)

  defp apply_execution_filters(query, opts) do
    query
    |> maybe_filter_execution_status(opts[:status])
    |> maybe_filter_session(opts[:session_id])
  end

  defp maybe_filter_execution_status(query, nil), do: query
  defp maybe_filter_execution_status(query, status), do: where(query, [e], e.status == ^status)

  defp maybe_filter_session(query, nil), do: query
  defp maybe_filter_session(query, session_id), do: where(query, [e], e.session_id == ^session_id)

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp attach_ai_telemetry(%Execution{} = execution) do
    handler_id = "command-pipeline-ai-#{execution.id}"

    events = [
      [:altar, :ai, :generate, :stop],
      [:altar, :ai, :embed, :stop],
      [:altar, :ai, :classify, :stop],
      [:altar, :ai, :code_gen, :stop]
    ]

    _ = :telemetry.detach(handler_id)

    _ =
      :telemetry.attach_many(
        handler_id,
        events,
        &handle_ai_event/4,
        %{execution_id: execution.id}
      )

    handler_id
  end

  defp detach_ai_telemetry(handler_id) do
    _ = :telemetry.detach(handler_id)
    :ok
  end

  defp handle_ai_event([:altar, :ai, operation, :stop], measurements, metadata, %{
         execution_id: execution_id
       }) do
    if Map.get(metadata, :command_workflow_id) == execution_id do
      attrs = build_ai_operation_attrs(operation, measurements, metadata, execution_id)

      case record_ai_operation(attrs) do
        {:ok, _} ->
          :ok

        {:error, changeset} ->
          Logger.debug("Failed to record AI operation: #{inspect(changeset)}")
      end
    end

    :ok
  end

  defp build_ai_operation_attrs(operation, measurements, metadata, execution_id) do
    tokens = Map.get(metadata, :tokens, %{})
    tokens_in = extract_tokens_in(tokens)
    tokens_out = extract_tokens_out(tokens)

    %{
      pipeline_run_id: execution_id,
      asset_name: Map.get(metadata, :asset) || Map.get(metadata, :asset_name) || "ai",
      operation: normalize_ai_operation(operation),
      provider: normalize_provider(metadata[:provider]),
      model: metadata[:model],
      tokens_in: tokens_in,
      tokens_out: tokens_out,
      cost_usd: calculate_cost_usd(metadata[:model], tokens_in, tokens_out),
      duration_ms: native_to_ms(measurements[:duration]),
      metadata: Map.drop(metadata, [:tokens])
    }
  end

  defp normalize_ai_operation(:code_gen), do: :code
  defp normalize_ai_operation(operation), do: operation

  defp normalize_provider(nil), do: nil
  defp normalize_provider(provider) when is_atom(provider), do: Atom.to_string(provider)
  defp normalize_provider(provider) when is_binary(provider), do: provider
  defp normalize_provider(provider), do: inspect(provider)

  defp extract_tokens_in(%{prompt: prompt}) when is_integer(prompt), do: prompt
  defp extract_tokens_in(%{input: input}) when is_integer(input), do: input
  defp extract_tokens_in(%{input_tokens: input}) when is_integer(input), do: input
  defp extract_tokens_in(_), do: 0

  defp extract_tokens_out(%{completion: completion}) when is_integer(completion), do: completion
  defp extract_tokens_out(%{output: output}) when is_integer(output), do: output
  defp extract_tokens_out(%{output_tokens: output}) when is_integer(output), do: output
  defp extract_tokens_out(_), do: 0

  defp calculate_cost_usd(nil, _tokens_in, _tokens_out), do: nil

  defp calculate_cost_usd(model, tokens_in, tokens_out) do
    case Altar.AI.Integrations.Command.calculate_cost(model, tokens_in, tokens_out) do
      nil -> nil
      cost when is_float(cost) -> Decimal.from_float(cost)
    end
  end

  defp native_to_ms(nil), do: nil

  defp native_to_ms(duration) when is_integer(duration) do
    System.convert_time_unit(duration, :native, :millisecond)
  end

  defp command_metadata_for_ai(%Execution{} = execution, opts) do
    base = %{
      command_session_id: execution.session_id,
      command_workflow_id: execution.id,
      command_user_id: execution.user_id
    }

    extra =
      [:command_session_id, :command_workflow_id, :command_user_id, :correlation_id]
      |> Enum.reduce(%{}, fn key, acc ->
        case Keyword.get(opts, key) do
          nil -> acc
          value -> Map.put(acc, key, value)
        end
      end)

    base
    |> Map.merge(extra)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
