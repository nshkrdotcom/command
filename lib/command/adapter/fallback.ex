defmodule Command.Adapter.Fallback do
  @moduledoc """
  Handles fallback generation for missing fields in compatibility mode.

  When running in compatibility mode, missing context-derived fields are
  auto-generated with UUID v4 values and telemetry warnings are emitted.
  This enables testing with partial provider responses while tracking
  fallback usage for monitoring.

  ## Fallback Policies

  | Field       | Strategy             | Telemetry Event                          |
  |-------------|---------------------|------------------------------------------|
  | session_id  | Generate UUID v4    | `[:command, :adapter, :fallback, :session_id]` |
  | run_id      | Generate UUID v4    | `[:command, :adapter, :fallback, :run_id]`     |
  | event_id    | Generate UUID v4    | `[:command, :adapter, :fallback, :event_id]`   |
  | timestamp   | `DateTime.utc_now/0` | `[:command, :adapter, :fallback, :timestamp]`  |
  | sequence    | Auto-increment      | `[:command, :adapter, :fallback, :sequence]`   |
  | data        | Empty map `%{}`     | `[:command, :adapter, :fallback, :data]`       |

  ## Example

      event = %Command.Event{type: :text_delta, provider: :claude, data: %{content: "hi"}}
      state = %{session_id: "s1", run_id: "r1", sequence: 5}
      filled = Command.Adapter.Fallback.apply_fallbacks(event, state)
      # => %Command.Event{session_id: "s1", run_id: "r1", sequence: 5, ...}
  """

  alias Command.Event

  @doc """
  Applies fallback values to any nil fields in the event.

  Uses state values first, then generates new values if necessary.
  Emits telemetry for each fallback applied.

  ## Parameters

  - `event` - A `Command.Event` struct with potentially nil fields
  - `state` - A map containing current adapter state (session_id, run_id, sequence)

  ## Returns

  The event with all nil fields filled with fallback values.
  """
  @spec apply_fallbacks(Event.t(), map()) :: Event.t()
  def apply_fallbacks(%Event{} = event, state) do
    event
    |> ensure_session_id(state)
    |> ensure_run_id(state)
    |> ensure_event_id()
    |> ensure_timestamp()
    |> ensure_sequence(state)
    |> ensure_data()
  end

  @doc """
  Generates a fallback value for a specific field and emits telemetry.

  ## Parameters

  - `field` - The field name (atom) to generate a fallback for

  ## Returns

  A UUID v4 string for identity fields.
  """
  @spec generate_fallback(atom()) :: String.t()
  def generate_fallback(field) do
    emit_fallback(field)
    generate_uuid()
  end

  # Private helpers

  defp ensure_session_id(%{session_id: nil} = event, state) do
    fallback = Map.get(state, :session_id) || generate_and_emit(:session_id)
    %{event | session_id: fallback}
  end

  defp ensure_session_id(event, _state), do: event

  defp ensure_run_id(%{run_id: nil} = event, state) do
    fallback = Map.get(state, :run_id) || generate_and_emit(:run_id)
    %{event | run_id: fallback}
  end

  defp ensure_run_id(event, _state), do: event

  defp ensure_event_id(%{event_id: nil} = event) do
    %{event | event_id: generate_and_emit(:event_id)}
  end

  defp ensure_event_id(event), do: event

  defp ensure_timestamp(%{timestamp: nil} = event) do
    emit_fallback(:timestamp)
    %{event | timestamp: DateTime.utc_now()}
  end

  defp ensure_timestamp(event), do: event

  defp ensure_sequence(%{sequence: nil} = event, state) do
    emit_fallback(:sequence)
    %{event | sequence: Map.get(state, :sequence, 0)}
  end

  defp ensure_sequence(event, _state), do: event

  defp ensure_data(%{data: nil} = event) do
    emit_fallback(:data)
    %{event | data: %{}}
  end

  defp ensure_data(event), do: event

  defp generate_and_emit(field) do
    emit_fallback(field)
    generate_uuid()
  end

  defp emit_fallback(field) do
    :telemetry.execute(
      [:command, :adapter, :fallback, field],
      %{count: 1},
      %{field: field}
    )
  end

  defp generate_uuid do
    <<a::48, _::4, b::12, _::2, c::62>> = :crypto.strong_rand_bytes(16)

    <<a::48, 4::4, b::12, 2::2, c::62>>
    |> Base.encode16(case: :lower)
    |> String.replace(~r/(.{8})(.{4})(.{4})(.{4})(.{12})/, "\\1-\\2-\\3-\\4-\\5")
  end
end
