defmodule Command.Orchestration do
  @moduledoc """
  Synapse orchestration context for Command.

  Provides database-backed agent configuration management, signal publishing,
  and helpers to integrate Synapse runtime state with Command sessions.

  ## Examples

      {:ok, _config} =
        Command.Orchestration.register_agent(%{
          id: :coordinator,
          type: :orchestrator,
          signals: %{subscribes: [:review_request], emits: [:review_summary]}
        })

      {:ok, _signal} = Command.Orchestration.publish(:review_request, %{review_id: "PR-123"})
  """

  require Logger
  import Ecto.Query

  alias Command.Orchestration.{AgentConfig, AgentConfigs, AgentSession}
  alias Command.Repo
  alias Command.Sessions.Session
  alias Synapse.Orchestrator.AgentConfig, as: SynapseAgentConfig
  alias Synapse.Orchestrator.Runtime, as: SynapseOrchestrator
  alias Synapse.Runtime, as: SynapseRuntime
  alias Synapse.SignalRouter

  @doc """
  Returns whether orchestration integration is enabled.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:command, __MODULE__, [])
    |> Keyword.get(:enabled, true)
  end

  @doc """
  Returns the configured Synapse runtime name.
  """
  @spec synapse_runtime_name() :: atom()
  def synapse_runtime_name do
    Application.get_env(:command, __MODULE__, [])
    |> Keyword.get(:synapse_runtime, SynapseRuntime)
  end

  @doc """
  Returns true if the Synapse runtime is available.
  """
  @spec runtime_available?() :: boolean()
  def runtime_available? do
    match?({:ok, _}, fetch_runtime())
  end

  @doc """
  Returns the configured orchestrator runtime name.
  """
  @spec orchestrator_name() :: atom()
  def orchestrator_name do
    Application.get_env(:command, __MODULE__, [])
    |> Keyword.get(:orchestrator_name, __MODULE__.Runtime)
  end

  @doc """
  Builds a child spec for the Synapse orchestrator runtime, if enabled.
  """
  @spec orchestrator_child_spec() :: Supervisor.child_spec() | nil
  def orchestrator_child_spec do
    if enabled?() do
      case fetch_runtime() do
        {:ok, runtime} ->
          opts = [
            name: orchestrator_name(),
            config_source: AgentConfigs,
            router: runtime.router,
            registry: runtime.registry,
            reconcile_interval: reconcile_interval()
          ]

          SynapseOrchestrator.child_spec(opts)

        {:error, reason} ->
          Logger.warning("Synapse runtime unavailable for orchestrator", reason: inspect(reason))
          nil
      end
    end
  end

  @doc """
  Returns the router for the active Synapse runtime.
  """
  @spec router() :: atom()
  def router do
    runtime = SynapseRuntime.fetch(synapse_runtime_name())
    runtime.router
  end

  @doc """
  Creates a new agent config record.
  """
  @spec create_agent_config(map()) :: {:ok, AgentConfig.t()} | {:error, Ecto.Changeset.t()}
  def create_agent_config(attrs) when is_map(attrs) do
    attrs = normalize_agent_config_attrs(attrs)

    %AgentConfig{}
    |> AgentConfig.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists agent configs with optional filters.
  """
  @spec list_agent_configs(keyword()) :: [AgentConfig.t()]
  def list_agent_configs(opts \\ []) do
    AgentConfig
    |> maybe_filter_status(opts[:status])
    |> order_by([c], asc: c.agent_id)
    |> Repo.all()
  end

  @doc """
  Fetches an agent config by ID.
  """
  @spec get_agent_config!(Ecto.UUID.t()) :: AgentConfig.t()
  def get_agent_config!(id), do: Repo.get!(AgentConfig, id)

  @doc """
  Registers a Synapse agent and persists its configuration.
  """
  @spec register_agent(map() | keyword()) :: {:ok, AgentConfig.t()} | {:error, term()}
  def register_agent(config) do
    with {:ok, validated} <- SynapseAgentConfig.new(config),
         {:ok, serialized} <- serialize_config(validated),
         {:ok, record} <- create_agent_config(attrs_from_synapse(validated, serialized)) do
      case Process.whereis(orchestrator_name()) do
        nil ->
          {:error, :orchestrator_unavailable}

        pid ->
          case SynapseOrchestrator.add_agent(pid, config) do
            {:ok, _pid} -> {:ok, record}
            {:error, reason} -> {:error, reason}
          end
      end
    end
  end

  @doc """
  Creates a new agent session record.
  """
  @spec create_agent_session(AgentConfig.t(), Session.t(), map()) ::
          {:ok, AgentSession.t()} | {:error, Ecto.Changeset.t()}
  def create_agent_session(%AgentConfig{} = config, %Session{} = session, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put(:agent_config_id, config.id)
      |> Map.put(:session_id, session.id)
      |> Map.put(:user_id, session.user_id)

    %AgentSession{}
    |> AgentSession.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Publishes a signal through Synapse's signal router.

  Adds Command context metadata when provided.
  """
  @spec publish(Synapse.Signal.topic(), map(), keyword()) ::
          {:ok, Jido.Signal.t()} | {:error, term()}
  def publish(topic, payload, opts \\ []) do
    meta =
      opts
      |> Keyword.get(:meta, %{})
      |> Map.merge(command_signal_metadata(opts))

    SignalRouter.publish(router(), topic, payload, Keyword.put(opts, :meta, meta))
  end

  defp attrs_from_synapse(%SynapseAgentConfig{} = config, serialized_config) do
    %{
      agent_id: Atom.to_string(config.id),
      type: config.type,
      status: :active,
      config: serialized_config,
      signals: serialize_signals(config.signals),
      metadata: config.metadata
    }
  end

  defp serialize_config(%SynapseAgentConfig{} = config) do
    config_map =
      config
      |> Map.from_struct()
      |> Map.drop([:__struct__])
      |> Map.put(:id, Atom.to_string(config.id))
      |> Map.put(:type, config.type)
      |> Map.update(:signals, %{}, &serialize_signals/1)
      |> Map.update(:actions, [], &serialize_modules/1)
      |> Map.update(:depends_on, [], &serialize_atoms/1)
      |> Map.update(:registry, nil, &serialize_module/1)
      |> Map.update(:orchestration, nil, &serialize_orchestration/1)
      |> Map.drop([:result_builder, :custom_handler, :spawn_condition])

    case find_serialization_error(config_map) do
      nil -> {:ok, config_map}
      reason -> {:error, reason}
    end
  end

  defp serialize_signals(%{subscribes: subs, emits: emits} = signals) do
    %{
      subscribes: serialize_atoms(subs),
      emits: serialize_atoms(emits),
      roles: serialize_roles(Map.get(signals, :roles))
    }
  end

  defp serialize_signals(other), do: other

  defp serialize_roles(nil), do: nil

  defp serialize_roles(%{} = roles) do
    roles
    |> Enum.map(fn {key, value} -> {Atom.to_string(key), serialize_atom(value)} end)
    |> Map.new()
  end

  defp serialize_orchestration(nil), do: nil

  defp serialize_orchestration(%{} = orchestration) do
    orchestration
    |> Enum.map(fn {key, value} -> {Atom.to_string(key), serialize_callable(value)} end)
    |> Map.new()
  end

  defp serialize_callable(value) when is_function(value), do: {:error, :non_serializable_callable}

  defp serialize_callable({module, function, args}) do
    %{
      module: serialize_module(module),
      function: serialize_atom(function),
      args: args
    }
  end

  defp serialize_callable(list) when is_list(list), do: Enum.map(list, &serialize_atom/1)
  defp serialize_callable(value), do: value

  defp serialize_module(nil), do: nil
  defp serialize_module(module) when is_atom(module), do: Atom.to_string(module)
  defp serialize_module(module) when is_binary(module), do: module

  defp serialize_modules(modules) when is_list(modules),
    do: Enum.map(modules, &serialize_module/1)

  defp serialize_modules(other), do: other

  defp serialize_atoms(atoms) when is_list(atoms), do: Enum.map(atoms, &serialize_atom/1)
  defp serialize_atoms(other), do: other

  defp serialize_atom(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp serialize_atom(atom) when is_binary(atom), do: atom
  defp serialize_atom(atom), do: atom

  defp find_serialization_error(value) when is_function(value), do: :non_serializable_callable
  defp find_serialization_error({:error, reason}), do: reason

  defp find_serialization_error(%{} = map) do
    map
    |> Map.values()
    |> Enum.reduce_while(nil, fn entry, _acc ->
      case find_serialization_error(entry) do
        nil -> {:cont, nil}
        reason -> {:halt, reason}
      end
    end)
  end

  defp find_serialization_error(list) when is_list(list) do
    Enum.reduce_while(list, nil, fn entry, _acc ->
      case find_serialization_error(entry) do
        nil -> {:cont, nil}
        reason -> {:halt, reason}
      end
    end)
  end

  defp find_serialization_error(_), do: nil

  defp command_signal_metadata(opts) do
    [:command_session_id, :command_workflow_id, :command_user_id, :correlation_id]
    |> Enum.reduce(%{}, fn key, acc ->
      case Keyword.get(opts, key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp normalize_agent_config_attrs(%{agent_id: agent_id} = attrs) when is_atom(agent_id) do
    %{attrs | agent_id: Atom.to_string(agent_id)}
  end

  defp normalize_agent_config_attrs(%{agent_id: agent_id} = attrs) when is_binary(agent_id) do
    attrs
  end

  defp normalize_agent_config_attrs(%{id: id} = attrs) when is_atom(id) do
    attrs
    |> Map.put_new(:agent_id, Atom.to_string(id))
    |> Map.delete(:id)
  end

  defp normalize_agent_config_attrs(%{id: id} = attrs) when is_binary(id) do
    attrs
    |> Map.put_new(:agent_id, id)
    |> Map.delete(:id)
  end

  defp normalize_agent_config_attrs(attrs), do: attrs

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [c], c.status == ^status)

  defp reconcile_interval do
    Application.get_env(:command, __MODULE__, [])
    |> Keyword.get(:reconcile_interval, 5_000)
  end

  defp fetch_runtime do
    {:ok, SynapseRuntime.fetch(synapse_runtime_name())}
  rescue
    error -> {:error, error}
  end
end
