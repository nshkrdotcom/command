defmodule Command.PromptSets.StateMachine do
  @moduledoc """
  State machine logic for prompt set runs and steps.

  This module defines the valid state transitions for runs and steps,
  and provides helpers for computing rollup statuses.

  ## Run States

  - `pending` - Not yet started
  - `running` - Currently executing
  - `paused` - Execution paused by user
  - `completed` - All steps completed successfully (terminal)
  - `partial_success` - Some repos succeeded, others failed (resumable)
  - `failed` - Run failed (terminal)
  - `aborted` - Run was aborted (terminal)

  ## Step States

  - `pending` - Not yet started
  - `running` - Currently executing
  - `completed` - Step completed successfully (terminal)
  - `partial_success` - Some repos succeeded, others failed (resumable)
  - `failed` - Step failed (terminal)
  - `skipped` - Step was skipped (terminal)

  ## State Classifications

  - **Terminal states**: No further transitions allowed
  - **Resumable states**: Can transition back to running

  ## Rollup Rules

  Rollups are evaluated **after the commit phase** for a step (i.e., once
  `prompt_repo_results.commit_status` is assigned for every repo in the step).
  """

  @run_states ~w(pending running paused completed partial_success failed aborted)
  @step_states ~w(pending running completed partial_success failed skipped)

  @run_terminal_states ~w(completed failed aborted)
  @run_resumable_states ~w(partial_success paused)

  @step_terminal_states ~w(completed failed skipped)
  @step_resumable_states ~w(partial_success)

  @run_transitions %{
    "pending" => ["running", "aborted"],
    "running" => ["completed", "partial_success", "failed", "paused", "aborted"],
    "paused" => ["running", "aborted"],
    "partial_success" => ["running"],
    "completed" => [],
    "failed" => [],
    "aborted" => []
  }

  @step_transitions %{
    "pending" => ["running", "skipped"],
    "running" => ["completed", "partial_success", "failed"],
    "partial_success" => ["running"],
    "completed" => [],
    "failed" => [],
    "skipped" => []
  }

  # ============================================================================
  # State Definitions
  # ============================================================================

  @doc "Returns all valid run states."
  @spec run_states() :: [String.t()]
  def run_states, do: @run_states

  @doc "Returns all valid step states."
  @spec step_states() :: [String.t()]
  def step_states, do: @step_states

  @doc "Returns terminal run states (no further transitions)."
  @spec run_terminal_states() :: [String.t()]
  def run_terminal_states, do: @run_terminal_states

  @doc "Returns terminal step states (no further transitions)."
  @spec step_terminal_states() :: [String.t()]
  def step_terminal_states, do: @step_terminal_states

  @doc "Returns resumable run states (can transition back to running)."
  @spec run_resumable_states() :: [String.t()]
  def run_resumable_states, do: @run_resumable_states

  @doc "Returns resumable step states (can transition back to running)."
  @spec step_resumable_states() :: [String.t()]
  def step_resumable_states, do: @step_resumable_states

  # ============================================================================
  # State Transitions
  # ============================================================================

  @doc """
  Checks if a run state transition is valid.

  ## Examples

      iex> StateMachine.valid_run_transition?("pending", "running")
      true

      iex> StateMachine.valid_run_transition?("completed", "running")
      false
  """
  @spec valid_run_transition?(String.t(), String.t()) :: boolean()
  def valid_run_transition?(from, to) do
    to in Map.get(@run_transitions, from, [])
  end

  @doc """
  Checks if a step state transition is valid.

  ## Examples

      iex> StateMachine.valid_step_transition?("pending", "running")
      true

      iex> StateMachine.valid_step_transition?("completed", "running")
      false
  """
  @spec valid_step_transition?(String.t(), String.t()) :: boolean()
  def valid_step_transition?(from, to) do
    to in Map.get(@step_transitions, from, [])
  end

  @doc """
  Returns the allowed transitions for a given run state.
  """
  @spec allowed_run_transitions(String.t()) :: [String.t()]
  def allowed_run_transitions(from) do
    Map.get(@run_transitions, from, [])
  end

  @doc """
  Returns the allowed transitions for a given step state.
  """
  @spec allowed_step_transitions(String.t()) :: [String.t()]
  def allowed_step_transitions(from) do
    Map.get(@step_transitions, from, [])
  end

  # ============================================================================
  # Rollup Helpers
  # ============================================================================

  @doc """
  Computes step status from repo results after the commit phase.

  This should only be called after all repos have a commit_status assigned.

  ## Policy Modes

  - `:fail_fast` - Fail on first repo failure
  - `:continue` - Continue with remaining repos, mark partial_success if threshold met
  - `:require_all` - Require all repos to succeed

  ## Examples

      iex> repo_results = [
      ...>   %{status: "completed"},
      ...>   %{status: "completed"},
      ...>   %{status: "failed"}
      ...> ]
      iex> StateMachine.compute_step_status(repo_results, %{mode: :continue, min_repos_percent: 50})
      "partial_success"
  """
  @spec compute_step_status(
          list(map()),
          map()
        ) :: String.t()
  def compute_step_status(repo_results, policy \\ %{mode: :continue, min_repos_percent: 50}) do
    statuses = Enum.map(repo_results, & &1.status)
    total = length(statuses)

    completed_count = Enum.count(statuses, &(&1 == "completed"))
    failed_count = Enum.count(statuses, &(&1 == "failed"))
    skipped_count = Enum.count(statuses, &(&1 == "skipped"))

    cond do
      # All skipped
      skipped_count == total ->
        "skipped"

      # All completed (including no_changes, no_commit)
      completed_count == total or
          (completed_count + skipped_count == total and completed_count > 0) ->
        "completed"

      # Any failed - check policy
      failed_count > 0 ->
        case policy[:mode] do
          :require_all ->
            "failed"

          :fail_fast ->
            "failed"

          _ ->
            # :continue mode - check threshold
            threshold = policy[:min_repos_percent] || 50
            completion_percent = completed_count / total * 100

            if completion_percent >= threshold do
              "partial_success"
            else
              "failed"
            end
        end

      # Edge case: still running or pending (shouldn't happen after commit phase)
      true ->
        "failed"
    end
  end

  @doc """
  Computes run status from step runs.

  ## Rules

  - If run was aborted: "aborted"
  - If fail_fast triggered or unrecoverable error: "failed"
  - If all steps terminal and none failed/partial_success: "completed"
  - If any step partial_success and no run-level failure: "partial_success"
  - Otherwise: "running"

  ## Options

  - `:aborted` - Set to true if run was explicitly aborted
  - `:fail_fast_triggered` - Set to true if fail_fast policy was triggered

  ## Examples

      iex> step_runs = [
      ...>   %{status: "completed"},
      ...>   %{status: "completed"},
      ...>   %{status: "failed"}
      ...> ]
      iex> StateMachine.compute_run_status(step_runs)
      "failed"
  """
  @spec compute_run_status(list(map()), keyword()) :: String.t()
  def compute_run_status(step_runs, opts \\ []) do
    if opts[:aborted] do
      "aborted"
    else
      if opts[:fail_fast_triggered] do
        "failed"
      else
        do_compute_run_status(step_runs)
      end
    end
  end

  defp do_compute_run_status(step_runs) do
    statuses = Enum.map(step_runs, & &1.status)

    all_terminal =
      Enum.all?(statuses, &(&1 in @step_terminal_states or &1 in @step_resumable_states))

    any_failed = Enum.any?(statuses, &(&1 == "failed"))
    any_partial = Enum.any?(statuses, &(&1 == "partial_success"))
    any_running = Enum.any?(statuses, &(&1 == "running" or &1 == "pending"))

    cond do
      any_running ->
        "running"

      any_failed ->
        "failed"

      any_partial ->
        "partial_success"

      all_terminal ->
        "completed"

      true ->
        "running"
    end
  end

  # ============================================================================
  # State Predicates
  # ============================================================================

  @doc "Returns true if the run state is terminal."
  @spec run_terminal?(String.t()) :: boolean()
  def run_terminal?(status), do: status in @run_terminal_states

  @doc "Returns true if the step state is terminal."
  @spec step_terminal?(String.t()) :: boolean()
  def step_terminal?(status), do: status in @step_terminal_states

  @doc "Returns true if the run state is resumable."
  @spec run_resumable?(String.t()) :: boolean()
  def run_resumable?(status), do: status in @run_resumable_states

  @doc "Returns true if the step state is resumable."
  @spec step_resumable?(String.t()) :: boolean()
  def step_resumable?(status), do: status in @step_resumable_states
end
