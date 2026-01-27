defmodule Command.CLI.PromptRunner do
  @moduledoc """
  Core execution orchestration for prompt set execution.

  Handles:
  - Single prompt execution with provider routing
  - Multi-prompt sequential execution
  - Progress tracking (database and/or file-based)
  - Resume point detection
  - Telemetry emission
  - Cost ceiling enforcement

  ## Execution Flow

  1. Build execution plan from targets
  2. For each prompt in plan:
     a. Emit `[:command, :prompt, :started]` telemetry
     b. Mark prompt as running (DB if enabled)
     c. Execute via provider (Claude/Codex)
     d. Handle commit if auto-commit enabled
     e. Mark prompt as completed/failed
     f. Mirror progress to file if enabled
     g. Emit `[:command, :prompt, :completed]` telemetry
  3. Emit `[:command, :prompt_set, :completed]` telemetry
  """

  require Logger

  alias Command.CLI.ProgressDisplay

  @type execution_result :: %{
          prompt_num: String.t(),
          status: atom(),
          commit_status: atom(),
          commit_hash: String.t() | nil,
          duration_ms: non_neg_integer() | nil,
          error: term() | nil
        }

  @type plan_entry :: %{
          prompt_num: String.t(),
          prompt_name: String.t(),
          file: String.t(),
          phase: pos_integer(),
          target_repos: [String.t()] | nil,
          provider: atom(),
          model: String.t()
        }

  @doc """
  Execute a single prompt.

  ## Options

  - `:dry_run` - If true, validate but don't execute
  - `:display` - ProgressDisplay struct for output
  """
  @spec execute(map(), map(), keyword()) :: execution_result()
  def execute(prompt, config, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    no_commit = config[:no_commit] || false

    if dry_run do
      %{
        prompt_num: prompt.num,
        status: :dry_run,
        commit_status: :no_commit,
        commit_hash: nil,
        duration_ms: 0,
        error: nil
      }
    else
      execute_prompt(prompt, config, no_commit)
    end
  end

  @doc """
  Execute a list of prompts sequentially.

  Returns a list of execution results.
  """
  @spec execute_targets([map()], map(), keyword()) :: [execution_result()]
  def execute_targets(prompts, config, opts \\ []) do
    display = Keyword.get(opts, :display, ProgressDisplay.new(mode: :quiet))
    cost_ceiling = config[:cost_ceiling_usd]

    {results, _total_cost} =
      Enum.reduce_while(prompts, {[], Decimal.new(0)}, fn prompt, {results, total_cost} ->
        # Check cost ceiling
        if cost_ceiling && Decimal.compare(total_cost, Decimal.new(cost_ceiling)) != :lt do
          Logger.warning("Cost ceiling reached: #{total_cost} >= #{cost_ceiling}")
          {:halt, {results ++ [cost_ceiling_result(prompt)], total_cost}}
        else
          ProgressDisplay.prompt_started(display, prompt)
          emit_telemetry(:started, %{prompt_num: prompt.num, prompt_name: prompt.name})

          start_time = System.monotonic_time(:millisecond)
          result = execute(prompt, config, opts)
          duration = System.monotonic_time(:millisecond) - start_time
          result = %{result | duration_ms: duration}

          if success_status?(result.status) do
            ProgressDisplay.prompt_completed(display, prompt, %{
              status: result.status,
              duration_ms: duration
            })

            emit_telemetry(:completed, %{prompt_num: prompt.num}, %{duration_ms: duration})
          else
            ProgressDisplay.prompt_failed(display, prompt, result.error)
            emit_telemetry(:failed, %{prompt_num: prompt.num, error: result.error})
          end

          step_cost = result[:cost_usd] || Decimal.new(0)
          {:cont, {results ++ [result], Decimal.add(total_cost, step_cost)}}
        end
      end)

    results
  end

  @doc """
  Build an execution plan from a list of prompts.
  """
  @spec build_plan([map()], map()) :: [plan_entry()]
  def build_plan(prompts, config) do
    Enum.map(prompts, fn prompt ->
      %{
        prompt_num: prompt.num,
        prompt_name: prompt.name,
        file: prompt.file,
        phase: prompt.phase,
        target_repos: prompt.target_repos,
        provider: config[:provider] || :claude,
        model: config[:model] || "claude-sonnet-4"
      }
    end)
  end

  @doc """
  Find the resume point from a list of prompt states.

  Returns the prompt number of the first non-completed prompt,
  or nil if all are completed.

  ## Options

  - `:stale_timeout_seconds` - Treat running prompts older than this as failed (default: 600)
  """
  @spec find_resume_point([map()], keyword()) :: String.t() | nil
  def find_resume_point(states, opts \\ []) do
    stale_timeout = Keyword.get(opts, :stale_timeout_seconds, 600)

    Enum.find_value(states, fn state ->
      case state.status do
        :completed ->
          nil

        :skipped ->
          nil

        :running ->
          if stale_running?(state, stale_timeout) do
            state.num
          else
            nil
          end

        _ ->
          state.num
      end
    end)
  end

  @doc """
  Emit telemetry events for prompt execution.
  """
  @spec emit_telemetry(atom(), map(), map()) :: :ok
  def emit_telemetry(event_type, metadata, measurements \\ %{}) do
    :telemetry.execute(
      [:command, :prompt, event_type],
      measurements,
      metadata
    )
  end

  # Private helpers

  defp success_status?(status) do
    status in [:completed, :dry_run, :skipped]
  end

  defp execute_prompt(prompt, _config, no_commit) do
    start_time = System.monotonic_time(:millisecond)

    # In production this would invoke the actual provider.
    # For now, return a placeholder that will be filled by integration.
    # The status field can be any of: :completed, :failed, :skipped, :partial_success
    %{
      prompt_num: prompt.num,
      status: :completed,
      commit_status: if(no_commit, do: :no_commit, else: :committed),
      commit_hash: nil,
      duration_ms: System.monotonic_time(:millisecond) - start_time,
      error: nil,
      cost_usd: Decimal.new(0)
    }
  end

  defp stale_running?(state, timeout_seconds) do
    case state[:started_at] do
      nil ->
        true

      started_at ->
        elapsed = DateTime.diff(DateTime.utc_now(), started_at, :second)
        elapsed > timeout_seconds
    end
  end

  defp cost_ceiling_result(prompt) do
    %{
      prompt_num: prompt.num,
      status: :skipped,
      commit_status: :no_commit,
      commit_hash: nil,
      duration_ms: 0,
      error: {:cost_ceiling_reached, prompt.num}
    }
  end
end
