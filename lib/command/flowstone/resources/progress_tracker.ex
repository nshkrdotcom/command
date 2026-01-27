defmodule Command.FlowStone.Resources.ProgressTracker do
  @moduledoc """
  Tracks pipeline execution progress and checkpoints.

  Provides DB-backed progress updates aligned with prompt_set_runs,
  prompt_step_runs, and prompt_repo_results.

  This resource implements the `FlowStone.Resource` behaviour and provides
  functions to track the progress of workflow automation runs at multiple levels:
  - Run-level: Overall prompt set execution
  - Step-level: Individual prompt execution
  - Repo-level: Per-repository results (for multi-repo prompts)

  ## Configuration

  Required config keys:
  - `:run_id` - UUID of the prompt_set_run being tracked

  ## Example

      config = %{run_id: "550e8400-e29b-41d4-a716-446655440000"}
      {:ok, progress} = ProgressTracker.setup(config)

      # Mark run as started
      :ok = ProgressTracker.mark_run_started(progress)

      # Track step progress
      :ok = ProgressTracker.mark_step_started(progress, step_id)
      :ok = ProgressTracker.mark_step_terminal(progress, step_id, "completed")

      # Track repo-level results
      :ok = ProgressTracker.mark_repo_terminal(progress, step_id, "command", %{
        status: "completed",
        commit_status: "committed",
        commit_hash: "abc123"
      })
  """

  use FlowStone.Resource

  @type t :: %{
          run_id: String.t()
        }

  @impl true
  def setup(config) do
    run_id = config[:run_id]

    if is_nil(run_id) do
      {:error, :run_id_required}
    else
      {:ok, %{run_id: run_id}}
    end
  end

  @doc """
  Mark a prompt_set_run as started.

  Updates the status to "running" and sets started_at timestamp.
  """
  @spec mark_run_started(t()) :: :ok | {:error, term()}
  def mark_run_started(%{run_id: run_id}) do
    # NOTE: This is a stub implementation until the prompt_set_runs table exists
    # When the schema is created, this should call:
    # Command.PromptSets.update_run(run_id, %{status: "running", started_at: DateTime.utc_now()})

    _ = run_id
    :ok
  end

  @doc """
  Mark a prompt_set_run as completed.

  Updates the status to "completed" and sets completed_at timestamp.
  """
  @spec mark_run_completed(t()) :: :ok | {:error, term()}
  def mark_run_completed(%{run_id: run_id}) do
    # NOTE: This is a stub implementation until the prompt_set_runs table exists
    # When the schema is created, this should call:
    # Command.PromptSets.update_run(run_id, %{status: "completed", completed_at: DateTime.utc_now()})

    _ = run_id
    :ok
  end

  @doc """
  Mark a prompt_step_run as started.

  Updates the step status to "running" and sets started_at timestamp.
  """
  @spec mark_step_started(t(), String.t()) :: :ok | {:error, term()}
  def mark_step_started(%{run_id: _run_id}, step_id) do
    # NOTE: This is a stub implementation until the prompt_step_runs table exists
    # When the schema is created, this should call:
    # Command.PromptSets.update_step(step_id, %{status: "running", started_at: DateTime.utc_now()})

    _ = step_id
    :ok
  end

  @doc """
  Mark a prompt_step_run as terminal (completed/failed/skipped).

  Updates the step status to the specified terminal status and merges
  additional attributes (e.g., completed_at, error details).

  ## Parameters

  - `progress` - The progress tracker state
  - `step_id` - UUID of the prompt_step_run
  - `status` - Terminal status ("completed", "failed", "skipped", "partial_success")
  - `attrs` - Additional attributes to update (optional)

  ## Examples

      ProgressTracker.mark_step_terminal(progress, step_id, "completed", %{
        completed_at: DateTime.utc_now(),
        tokens_used: 1500
      })

      ProgressTracker.mark_step_terminal(progress, step_id, "failed", %{
        error: "LLM execution failed"
      })
  """
  @spec mark_step_terminal(t(), String.t(), String.t(), map()) :: :ok | {:error, term()}
  def mark_step_terminal(%{run_id: _run_id}, step_id, status, attrs \\ %{}) do
    # NOTE: This is a stub implementation until the prompt_step_runs table exists
    # When the schema is created, this should call:
    # Command.PromptSets.update_step(step_id, Map.put(attrs, :status, status))

    _ = step_id
    _ = status
    _ = attrs
    :ok
  end

  @doc """
  Mark a prompt_repo_result as terminal.

  Updates the repo result status and commit_status, along with any additional
  attributes like commit_hash, error details, etc.

  ## Parameters

  - `progress` - The progress tracker state
  - `step_id` - UUID of the parent prompt_step_run
  - `repo_name` - Name of the repository (e.g., "command", "flowstone")
  - `attrs` - Attributes including status, commit_status, and others

  ## Examples

      ProgressTracker.mark_repo_terminal(progress, step_id, "command", %{
        status: "completed",
        commit_status: "committed",
        commit_hash: "abc123def",
        files_changed: 5
      })

      ProgressTracker.mark_repo_terminal(progress, step_id, "flowstone", %{
        status: "failed",
        commit_status: "failed",
        error: "Merge conflict"
      })
  """
  @spec mark_repo_terminal(t(), String.t(), String.t(), map()) :: :ok | {:error, term()}
  def mark_repo_terminal(%{run_id: _run_id}, step_id, repo_name, attrs \\ %{}) do
    # NOTE: This is a stub implementation until the prompt_repo_results table exists
    # When the schema is created, this should call:
    # Command.PromptSets.update_repo_result(step_id, repo_name, attrs)

    _ = step_id
    _ = repo_name
    _ = attrs
    :ok
  end
end
