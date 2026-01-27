defmodule Command.PromptSets do
  @moduledoc """
  Context for managing prompt sets and their execution runs.

  Prompt sets define a sequence of prompts to be executed in order.
  Each run tracks progress, token usage, and costs.

  ## Overview

  A prompt set contains:
  - A list of prompt definitions (name, file, provider, model, etc.)
  - Configuration for execution (directories, tools, permissions)
  - Commit message templates

  A prompt set run tracks:
  - Progress through the prompt sequence
  - Per-step token usage and cost
  - Aggregate metrics across all steps
  - Error state and resume capability

  ## State Machine

  See `Command.PromptSets.StateMachine` for state transition rules.
  """

  import Ecto.Query, warn: false

  alias Command.Repo

  alias Command.PromptSets.{
    PromptSet,
    PromptSetRun,
    PromptStepRun,
    PromptChangeset,
    PromptRepoResult
  }

  alias Command.PromptSets.StateMachine

  # ============================================================================
  # PromptSet CRUD
  # ============================================================================

  @doc """
  Creates a new prompt set.

  ## Examples

      iex> create_prompt_set(%{name: "My Set", slug: "my-set"})
      {:ok, %PromptSet{}}

      iex> create_prompt_set(%{})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_prompt_set(map()) :: {:ok, PromptSet.t()} | {:error, Ecto.Changeset.t()}
  def create_prompt_set(attrs) do
    %PromptSet{}
    |> PromptSet.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a prompt set by ID. Returns nil if not found.
  """
  @spec get_prompt_set(Ecto.UUID.t()) :: PromptSet.t() | nil
  def get_prompt_set(id) do
    Repo.get(PromptSet, id)
  end

  @doc """
  Gets a prompt set by ID. Raises if not found.
  """
  @spec get_prompt_set!(Ecto.UUID.t()) :: PromptSet.t()
  def get_prompt_set!(id) do
    Repo.get!(PromptSet, id)
  end

  @doc """
  Gets a prompt set by slug. Returns nil if not found.
  """
  @spec get_prompt_set_by_slug(String.t()) :: PromptSet.t() | nil
  def get_prompt_set_by_slug(slug) do
    Repo.get_by(PromptSet, slug: slug)
  end

  @doc """
  Lists prompt sets with optional filters.

  When called without arguments, returns all active prompt sets.

  ## Options

  - `:status` - Filter by status
  - `:doc_set_id` - Filter by document set ID
  """
  @spec list_prompt_sets(keyword()) :: [PromptSet.t()]
  def list_prompt_sets(filters \\ []) do
    query = from(ps in PromptSet, order_by: [desc: ps.inserted_at])

    query =
      case Keyword.get(filters, :status) do
        nil ->
          if Keyword.keys(filters) == [] do
            from(ps in query, where: ps.status == "active")
          else
            query
          end

        status ->
          from(ps in query, where: ps.status == ^status)
      end

    query =
      case Keyword.get(filters, :doc_set_id) do
        nil -> query
        doc_set_id -> from(ps in query, where: ps.doc_set_id == ^doc_set_id)
      end

    Repo.all(query)
  end

  @doc """
  Updates a prompt set.
  """
  @spec update_prompt_set(PromptSet.t(), map()) ::
          {:ok, PromptSet.t()} | {:error, Ecto.Changeset.t()}
  def update_prompt_set(%PromptSet{} = prompt_set, attrs) do
    prompt_set
    |> PromptSet.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft deletes a prompt set by archiving it.
  """
  @spec delete_prompt_set(PromptSet.t()) :: {:ok, PromptSet.t()} | {:error, Ecto.Changeset.t()}
  def delete_prompt_set(%PromptSet{} = prompt_set) do
    update_prompt_set(prompt_set, %{status: "archived"})
  end

  @doc """
  Returns a changeset for tracking prompt set changes.
  """
  @spec change_prompt_set(PromptSet.t(), map()) :: Ecto.Changeset.t()
  def change_prompt_set(%PromptSet{} = prompt_set, attrs \\ %{}) do
    PromptSet.changeset(prompt_set, attrs)
  end

  # ============================================================================
  # PromptSetRun Operations
  # ============================================================================

  @doc """
  Creates a new run for a prompt set.

  Initializes step_runs for all prompts in the prompt set.

  ## Options

  - `:pipeline_run_id` - Optional FlowStone pipeline run ID
  - `:branch_name` - Optional branch name
  - `:branch_strategy` - Optional branch strategy mode
  """
  @spec create_run(PromptSet.t(), keyword()) ::
          {:ok, PromptSetRun.t()} | {:error, Ecto.Changeset.t()}
  def create_run(%PromptSet{} = prompt_set, opts \\ []) do
    prompts = prompt_set.prompts || []

    run_attrs = %{
      prompt_set_id: prompt_set.id,
      pipeline_run_id: Keyword.get(opts, :pipeline_run_id),
      branch_name: Keyword.get(opts, :branch_name),
      branch_strategy: Keyword.get(opts, :branch_strategy),
      config_snapshot: prompt_set.config,
      total_prompts: length(prompts)
    }

    Repo.transaction(fn ->
      # Create the run
      {:ok, run} =
        %PromptSetRun{}
        |> PromptSetRun.changeset(run_attrs)
        |> Repo.insert()

      # Create step_runs for each prompt
      Enum.each(prompts, fn prompt ->
        %PromptStepRun{}
        |> PromptStepRun.changeset(%{
          prompt_set_run_id: run.id,
          prompt_num: prompt["num"]
        })
        |> Repo.insert!()
      end)

      run
    end)
  end

  @doc """
  Gets a run by ID with preloaded associations.
  """
  @spec get_run(Ecto.UUID.t()) :: PromptSetRun.t() | nil
  def get_run(id) do
    PromptSetRun
    |> Repo.get(id)
    |> case do
      nil -> nil
      run -> Repo.preload(run, [:prompt_set, :step_runs])
    end
  end

  @doc """
  Gets a run by ID with preloaded associations. Raises if not found.
  """
  @spec get_run!(Ecto.UUID.t()) :: PromptSetRun.t()
  def get_run!(id) do
    PromptSetRun
    |> Repo.get!(id)
    |> Repo.preload([:prompt_set, :step_runs])
  end

  @doc """
  Lists runs for a specific prompt set.
  """
  @spec list_runs_for_prompt_set(Ecto.UUID.t()) :: [PromptSetRun.t()]
  def list_runs_for_prompt_set(prompt_set_id) do
    from(r in PromptSetRun,
      where: r.prompt_set_id == ^prompt_set_id,
      order_by: [desc: r.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Lists active runs (pending, running, or paused).
  """
  @spec list_active_runs() :: [PromptSetRun.t()]
  def list_active_runs do
    from(r in PromptSetRun,
      where: r.status in ["pending", "running", "paused"],
      order_by: [desc: r.inserted_at]
    )
    |> Repo.all()
  end

  # ============================================================================
  # PromptStepRun Operations
  # ============================================================================

  @doc """
  Gets a step run by run_id and prompt_num.
  """
  @spec get_step_run(Ecto.UUID.t(), String.t()) :: PromptStepRun.t() | nil
  def get_step_run(run_id, prompt_num) do
    Repo.get_by(PromptStepRun, prompt_set_run_id: run_id, prompt_num: prompt_num)
  end

  @doc """
  Updates a step's status and additional attributes.
  """
  @spec update_step_status(PromptStepRun.t(), String.t(), map()) ::
          {:ok, PromptStepRun.t()} | {:error, Ecto.Changeset.t()}
  def update_step_status(%PromptStepRun{} = step, status, attrs \\ %{}) do
    step
    |> PromptStepRun.changeset(Map.put(attrs, :status, status))
    |> Repo.update()
  end

  # ============================================================================
  # PromptChangeset Operations
  # ============================================================================

  @doc """
  Creates a prompt-scoped changeset for a step.
  """
  @spec create_prompt_changeset(PromptStepRun.t(), map()) ::
          {:ok, PromptChangeset.t()} | {:error, Ecto.Changeset.t()}
  def create_prompt_changeset(%PromptStepRun{} = step, attrs \\ %{}) do
    attrs =
      Map.merge(attrs, %{
        scope: "prompt",
        prompt_step_run_id: step.id,
        prompt_set_run_id: step.prompt_set_run_id
      })

    %PromptChangeset{}
    |> PromptChangeset.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a run-scoped changeset for a run.
  """
  @spec create_run_changeset(PromptSetRun.t(), map()) ::
          {:ok, PromptChangeset.t()} | {:error, Ecto.Changeset.t()}
  def create_run_changeset(%PromptSetRun{} = run, attrs \\ %{}) do
    attrs =
      Map.merge(attrs, %{
        scope: "run",
        prompt_set_run_id: run.id,
        prompt_step_run_id: nil
      })

    %PromptChangeset{}
    |> PromptChangeset.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a changeset's status.
  """
  @spec update_changeset_status(PromptChangeset.t(), String.t(), map()) ::
          {:ok, PromptChangeset.t()} | {:error, Ecto.Changeset.t()}
  def update_changeset_status(%PromptChangeset{} = changeset, status, attrs \\ %{}) do
    changeset
    |> PromptChangeset.changeset(Map.put(attrs, :status, status))
    |> Repo.update()
  end

  # ============================================================================
  # PromptRepoResult Operations
  # ============================================================================

  @doc """
  Creates or updates a repo result for a step.

  Uses upsert semantics - if a result already exists for the step+repo combination,
  it will be updated.
  """
  @spec upsert_repo_result(PromptStepRun.t(), String.t(), map()) ::
          {:ok, PromptRepoResult.t()} | {:error, Ecto.Changeset.t()}
  def upsert_repo_result(%PromptStepRun{} = step, repo_name, attrs \\ %{}) do
    case Repo.get_by(PromptRepoResult, prompt_step_run_id: step.id, repo_name: repo_name) do
      nil ->
        attrs = Map.merge(attrs, %{prompt_step_run_id: step.id, repo_name: repo_name})

        %PromptRepoResult{}
        |> PromptRepoResult.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> PromptRepoResult.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Lists repo results for a step, ordered by repo_name.
  """
  @spec list_repo_results(Ecto.UUID.t()) :: [PromptRepoResult.t()]
  def list_repo_results(step_id) do
    from(r in PromptRepoResult,
      where: r.prompt_step_run_id == ^step_id,
      order_by: [asc: r.repo_name]
    )
    |> Repo.all()
  end

  # ============================================================================
  # Run State Machine
  # ============================================================================

  @doc """
  Starts a run (transitions pending -> running).
  """
  @spec start_run(PromptSetRun.t()) :: {:ok, PromptSetRun.t()} | {:error, :invalid_transition}
  def start_run(%PromptSetRun{} = run) do
    if StateMachine.valid_run_transition?(run.status, "running") do
      run
      |> PromptSetRun.changeset(%{status: "running", started_at: DateTime.utc_now()})
      |> Repo.update()
    else
      {:error, :invalid_transition}
    end
  end

  @doc """
  Pauses a run (transitions running -> paused).
  """
  @spec pause_run(PromptSetRun.t()) :: {:ok, PromptSetRun.t()} | {:error, :invalid_transition}
  def pause_run(%PromptSetRun{} = run) do
    if StateMachine.valid_run_transition?(run.status, "paused") do
      run
      |> PromptSetRun.changeset(%{status: "paused"})
      |> Repo.update()
    else
      {:error, :invalid_transition}
    end
  end

  @doc """
  Resumes a run (transitions paused/partial_success -> running).
  """
  @spec resume_run(PromptSetRun.t()) :: {:ok, PromptSetRun.t()} | {:error, :invalid_transition}
  def resume_run(%PromptSetRun{} = run) do
    if StateMachine.valid_run_transition?(run.status, "running") do
      run
      |> PromptSetRun.changeset(%{status: "running"})
      |> Repo.update()
    else
      {:error, :invalid_transition}
    end
  end

  @doc """
  Completes a run (transitions running -> completed).
  """
  @spec complete_run(PromptSetRun.t()) :: {:ok, PromptSetRun.t()} | {:error, :invalid_transition}
  def complete_run(%PromptSetRun{} = run) do
    if StateMachine.valid_run_transition?(run.status, "completed") do
      run
      |> PromptSetRun.changeset(%{status: "completed", completed_at: DateTime.utc_now()})
      |> Repo.update()
    else
      {:error, :invalid_transition}
    end
  end

  @doc """
  Fails a run (transitions running -> failed).
  """
  @spec fail_run(PromptSetRun.t(), String.t()) ::
          {:ok, PromptSetRun.t()} | {:error, :invalid_transition}
  def fail_run(%PromptSetRun{} = run, error_summary) do
    if StateMachine.valid_run_transition?(run.status, "failed") do
      run
      |> PromptSetRun.changeset(%{
        status: "failed",
        error_summary: error_summary,
        completed_at: DateTime.utc_now()
      })
      |> Repo.update()
    else
      {:error, :invalid_transition}
    end
  end

  @doc """
  Aborts a run (transitions pending/running/paused -> aborted).
  """
  @spec abort_run(PromptSetRun.t()) :: {:ok, PromptSetRun.t()} | {:error, :invalid_transition}
  def abort_run(%PromptSetRun{} = run) do
    if StateMachine.valid_run_transition?(run.status, "aborted") do
      run
      |> PromptSetRun.changeset(%{status: "aborted", completed_at: DateTime.utc_now()})
      |> Repo.update()
    else
      {:error, :invalid_transition}
    end
  end

  # ============================================================================
  # Step State Machine
  # ============================================================================

  @doc """
  Starts a step (transitions pending -> running).
  """
  @spec start_step(PromptStepRun.t()) :: {:ok, PromptStepRun.t()} | {:error, :invalid_transition}
  def start_step(%PromptStepRun{} = step) do
    if StateMachine.valid_step_transition?(step.status, "running") do
      step
      |> PromptStepRun.changeset(%{status: "running", started_at: DateTime.utc_now()})
      |> Repo.update()
    else
      {:error, :invalid_transition}
    end
  end

  @doc """
  Completes a step with usage metrics.

  Updates the step with usage data and atomically updates run aggregates.

  ## Parameters

  - `step` - The step to complete
  - `usage` - Map with `:input_tokens`, `:output_tokens`, `:cost_usd`
  - `final_status` - Status to set ("completed" or "partial_success"), defaults to "completed"
  """
  @spec complete_step(PromptStepRun.t(), map(), String.t()) ::
          {:ok, PromptStepRun.t()} | {:error, :invalid_transition | Ecto.Changeset.t()}
  def complete_step(%PromptStepRun{} = step, usage, final_status \\ "completed") do
    if StateMachine.valid_step_transition?(step.status, final_status) do
      Repo.transaction(fn ->
        # Update step with usage and terminal status
        {:ok, updated_step} =
          step
          |> PromptStepRun.changeset(%{
            status: final_status,
            input_tokens: usage[:input_tokens] || 0,
            output_tokens: usage[:output_tokens] || 0,
            cost_usd: usage[:cost_usd] || Decimal.new(0),
            completed_at: DateTime.utc_now()
          })
          |> Repo.update()

        # Update run aggregates
        completed_inc = if final_status == "completed", do: 1, else: 0

        from(r in PromptSetRun,
          where: r.id == ^step.prompt_set_run_id,
          update: [
            inc: [
              completed_prompts: ^completed_inc,
              total_input_tokens: ^(usage[:input_tokens] || 0),
              total_output_tokens: ^(usage[:output_tokens] || 0),
              total_cost_usd: ^(usage[:cost_usd] || Decimal.new(0))
            ]
          ]
        )
        |> Repo.update_all([])

        updated_step
      end)
    else
      {:error, :invalid_transition}
    end
  end

  @doc """
  Fails a step with error details.
  """
  @spec fail_step(PromptStepRun.t(), map()) ::
          {:ok, PromptStepRun.t()} | {:error, :invalid_transition | Ecto.Changeset.t()}
  def fail_step(%PromptStepRun{} = step, error_details) do
    if StateMachine.valid_step_transition?(step.status, "failed") do
      Repo.transaction(fn ->
        {:ok, updated_step} =
          step
          |> PromptStepRun.changeset(%{
            status: "failed",
            error_type: error_details[:error_type],
            error_message: error_details[:error_message],
            completed_at: DateTime.utc_now()
          })
          |> Repo.update()

        # Update run failed count
        from(r in PromptSetRun,
          where: r.id == ^step.prompt_set_run_id,
          update: [inc: [failed_prompts: 1]]
        )
        |> Repo.update_all([])

        updated_step
      end)
    else
      {:error, :invalid_transition}
    end
  end

  @doc """
  Skips a step (transitions pending -> skipped).
  """
  @spec skip_step(PromptStepRun.t()) :: {:ok, PromptStepRun.t()} | {:error, :invalid_transition}
  def skip_step(%PromptStepRun{} = step) do
    if StateMachine.valid_step_transition?(step.status, "skipped") do
      step
      |> PromptStepRun.changeset(%{status: "skipped"})
      |> Repo.update()
    else
      {:error, :invalid_transition}
    end
  end

  # ============================================================================
  # Resume Point
  # ============================================================================

  @doc """
  Returns the first non-completed step (the resume point).

  By default, skips partial_success steps (treats them as "done enough").

  ## Options

  - `:mode` - Resume mode: `:continue` (default) or `:partial_continue`
  - `:policy` - Policy mode: `:fail_fast`, `:continue` (default), or `:require_all`
  """
  @spec resume_point(Ecto.UUID.t(), keyword()) ::
          PromptStepRun.t() | nil | {:error, atom(), String.t(), String.t()}
  def resume_point(run_id, opts \\ []) do
    mode = Keyword.get(opts, :mode, :continue)
    policy = Keyword.get(opts, :policy, :continue)

    case {mode, policy} do
      {:partial_continue, _} ->
        # Only select partial_success steps for targeted retry
        first_partial_success_step(run_id)

      {:force_continue, :require_all} ->
        # Explicit override: skip partial_success even under require_all
        first_non_terminal_step(run_id, ["completed", "skipped", "partial_success"])

      {:continue, :require_all} ->
        # Under require_all, partial_success blocks --continue
        step = first_non_terminal_step(run_id, ["completed", "skipped"])

        case step do
          %{status: "partial_success"} = s ->
            {:error, :partial_blocks_continue,
             "partial_success blocks --continue under require_all; " <>
               "use --partial-continue to retry or --force-continue to override", s.prompt_num}

          step ->
            step
        end

      {:continue, _} ->
        # Under fail_fast/continue, skip partial_success (treated as "done enough")
        first_non_terminal_step(run_id, ["completed", "skipped", "partial_success"])
    end
  end

  defp first_partial_success_step(run_id) do
    from(s in PromptStepRun,
      where: s.prompt_set_run_id == ^run_id,
      where: s.status == "partial_success",
      order_by: [asc: s.prompt_num],
      limit: 1
    )
    |> Repo.one()
  end

  defp first_non_terminal_step(run_id, excluded_statuses) do
    from(s in PromptStepRun,
      where: s.prompt_set_run_id == ^run_id,
      where: s.status not in ^excluded_statuses,
      order_by: [asc: s.prompt_num],
      limit: 1
    )
    |> Repo.one()
  end

  # ============================================================================
  # Cost Tracking
  # ============================================================================

  @doc """
  Returns the total cost for a run.
  """
  @spec get_run_cost(Ecto.UUID.t()) :: Decimal.t()
  def get_run_cost(run_id) do
    case Repo.get(PromptSetRun, run_id) do
      nil -> Decimal.new(0)
      run -> run.total_cost_usd
    end
  end
end
