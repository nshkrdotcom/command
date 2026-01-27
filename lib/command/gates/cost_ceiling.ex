defmodule Command.Gates.CostCeiling do
  @moduledoc """
  Cost ceiling enforcement gate (GATE-OPS-002).

  Uses Decimal arithmetic throughout for financial precision. Evaluates
  whether the current run cost plus event cost exceeds the configured ceiling.

  ## Behavior

  - Cost at or above ceiling: FAIL (strict less-than required to pass)
  - Cost below ceiling: PASS
  - Nil event cost treated as zero
  - Negative cost returns error
  - Default per-run ceiling: $50.00
  - Default per-session ceiling: $500.00

  ## Telemetry

  Emits:
  - `[:command, :gates, :cost_ceiling, :evaluated]` on every evaluation
  - `[:command, :gates, :cost_ceiling, :exceeded]` when ceiling is exceeded
  """

  @default_per_run_ceiling Decimal.new("50.00")
  @default_per_session_ceiling Decimal.new("500.00")

  @doc """
  Returns the default per-run cost ceiling.
  """
  @spec default_run_ceiling() :: Decimal.t()
  def default_run_ceiling, do: @default_per_run_ceiling

  @doc """
  Returns the default per-session cost ceiling.
  """
  @spec default_session_ceiling() :: Decimal.t()
  def default_session_ceiling, do: @default_per_session_ceiling

  @doc """
  Evaluate whether the cost is within the ceiling.

  The `run_context` must have:
  - `usage.total_cost_usd` - Current accumulated cost (Decimal)
  - `config.cost_ceiling_usd` - Optional per-run ceiling (Decimal)

  The `event` must have:
  - `usage.total_cost_usd` - Cost from this event (Decimal or nil)

  Alternatively, the event may have a nested structure:
  - `data.usage.total_cost_usd` - Cost from nested event data

  Returns:
  - `:pass` when total cost is strictly less than ceiling
  - `{:fail, details}` when total cost >= ceiling
  - `{:error, :invalid_cost}` when event cost is negative
  """
  @spec evaluate(map(), map()) :: :pass | {:fail, map()} | {:error, :invalid_cost}
  def evaluate(run_context, event) do
    event_cost = extract_event_cost(event)

    case validate_cost(event_cost) do
      :ok ->
        current_total = run_context.usage.total_cost_usd
        new_total = Decimal.add(current_total, event_cost)
        ceiling = get_ceiling(run_context)

        result =
          case Decimal.compare(new_total, ceiling) do
            :lt ->
              :pass

            _ ->
              exceeded_by = Decimal.sub(new_total, ceiling)

              {:fail,
               %{
                 current: new_total,
                 ceiling: ceiling,
                 exceeded_by: exceeded_by
               }}
          end

        emit_evaluated_telemetry(new_total, ceiling, result)

        case result do
          {:fail, details} ->
            emit_exceeded_telemetry(details)
            result

          _ ->
            result
        end

      {:error, _} = err ->
        err
    end
  end

  # -- Private --

  defp extract_event_cost(event) do
    # Try direct path first
    cost = get_in(event, [:usage, :total_cost_usd]) || get_in(event, ["usage", "total_cost_usd"])

    # Try nested data path
    cost =
      cost ||
        get_in(event, [:data, :usage, :total_cost_usd]) ||
        get_in(event, ["data", "usage", "total_cost_usd"])

    case cost do
      nil -> Decimal.new("0")
      %Decimal{} -> cost
      n when is_number(n) -> Decimal.new(to_string(n))
      s when is_binary(s) -> Decimal.new(s)
    end
  end

  defp validate_cost(cost) do
    if Decimal.compare(cost, Decimal.new("0")) == :lt do
      {:error, :invalid_cost}
    else
      :ok
    end
  end

  defp get_ceiling(run_context) do
    config = run_context[:config] || %{}
    config[:cost_ceiling_usd] || config["cost_ceiling_usd"] || @default_per_run_ceiling
  end

  defp emit_evaluated_telemetry(current_cost, ceiling, result) do
    result_atom =
      case result do
        :pass -> :pass
        {:fail, _} -> :fail
      end

    :telemetry.execute(
      [:command, :gates, :cost_ceiling, :evaluated],
      %{current_cost: current_cost, ceiling: ceiling},
      %{result: result_atom}
    )
  end

  defp emit_exceeded_telemetry(%{current: current, ceiling: ceiling, exceeded_by: exceeded_by}) do
    :telemetry.execute(
      [:command, :gates, :cost_ceiling, :exceeded],
      %{exceeded_by: exceeded_by},
      %{current_cost: current, ceiling: ceiling}
    )
  end
end
