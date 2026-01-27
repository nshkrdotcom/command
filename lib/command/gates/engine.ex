defmodule Command.Gates.Engine do
  @moduledoc """
  Engine for evaluating quality gates against criteria.

  The engine loads gate specifications, evaluates all criteria against a provided
  context, emits telemetry events, and records results. Gate evaluation is
  idempotent - evaluating the same gate with the same context produces the same result.

  ## Usage

      # Evaluate with a known gate spec
      Engine.evaluate_gate("GATE-IMPL-006", %{coverage: 85}, spec: spec)

      # Evaluate by loading spec from definitions
      Engine.evaluate_gate("GATE-DOC-001", %{docs_path: "/path/to/docs"})

      # Load a gate spec
      {:ok, spec} = Engine.load_gate_spec("GATE-DOC-001")

  ## Telemetry

  Emits `[:command, :gates, :evaluated]` with:
  - Measurements: `%{duration_ms: integer()}`
  - Metadata: `%{gate_id: string, result: :pass | :fail, criteria_results: list}`
  """

  alias Command.Gates.{GateSpec, Definitions}

  @doc """
  Evaluate a gate against its criteria.

  Options:
  - `:spec` - Provide a GateSpec directly instead of loading from definitions

  Returns `:pass` when all required criteria pass, or `{:fail, results}` with
  the full list of criterion results when any required criterion fails.
  """
  @spec evaluate_gate(String.t(), map(), keyword()) :: :pass | {:fail, [tuple()]}
  def evaluate_gate(gate_id, context, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    spec =
      case Keyword.get(opts, :spec) do
        nil ->
          case load_gate_spec(gate_id) do
            {:ok, s} -> s
            {:error, _} -> %GateSpec{id: gate_id, criteria: []}
          end

        s ->
          s
      end

    do_evaluate_with_retry(gate_id, context, spec, start_time)
  end

  @doc """
  Load a gate specification by ID.

  Returns `{:ok, spec}` for known gates or `{:error, :not_found}` for unknown.
  """
  @spec load_gate_spec(String.t()) :: {:ok, GateSpec.t()} | {:error, :not_found}
  def load_gate_spec(gate_id) do
    case Enum.find(Definitions.all_gates(), fn spec -> spec.id == gate_id end) do
      nil -> {:error, :not_found}
      spec -> {:ok, spec}
    end
  end

  # -- Private --

  defp do_evaluate_with_retry(gate_id, context, spec, start_time) do
    retry_config = spec.retry_config || %{max_retries: 0, backoff_ms: [], auto_retry: false}
    max_attempts = if retry_config.auto_retry, do: retry_config.max_retries + 1, else: 1
    backoffs = retry_config[:backoff_ms] || retry_config.backoff_ms || []

    do_retry(gate_id, context, spec, start_time, 0, max_attempts, backoffs)
  end

  defp do_retry(gate_id, context, spec, start_time, attempt, max_attempts, backoffs) do
    results = evaluate_all_criteria(spec.criteria, context)

    all_required_pass =
      Enum.all?(results, fn {_name, result} ->
        result == :pass
      end)

    if all_required_pass do
      duration = System.monotonic_time(:millisecond) - start_time
      emit_telemetry(gate_id, :pass, results, duration)
      :pass
    else
      next_attempt = attempt + 1

      if next_attempt < max_attempts do
        # Sleep for backoff before retry
        backoff = Enum.at(backoffs, attempt, 0)
        if backoff > 0, do: Process.sleep(backoff)
        do_retry(gate_id, context, spec, start_time, next_attempt, max_attempts, backoffs)
      else
        duration = System.monotonic_time(:millisecond) - start_time
        emit_telemetry(gate_id, :fail, results, duration)
        {:fail, results}
      end
    end
  end

  defp evaluate_all_criteria(criteria, context) do
    Enum.map(criteria, fn criterion ->
      result = evaluate_criterion(criterion, context)
      {criterion.name, result}
    end)
  end

  defp evaluate_criterion(criterion, context) do
    criterion.evaluator.(context)
  rescue
    e ->
      {:error, Exception.message(e)}
  end

  defp emit_telemetry(gate_id, result, criteria_results, duration_ms) do
    :telemetry.execute(
      [:command, :gates, :evaluated],
      %{duration_ms: duration_ms},
      %{
        gate_id: gate_id,
        result: result,
        criteria_results: criteria_results,
        evaluated_at: DateTime.utc_now()
      }
    )
  end
end
