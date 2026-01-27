defmodule Command.Stream do
  @moduledoc """
  Unified stream handling for multi-provider agent interactions.

  This module provides stream transformation utilities for working with
  portfolio AgentSession event streams. It handles common stream
  transformations like buffering and telemetry emission.

  Event normalization (converting raw provider events to `Command.Event`
  structs) is now handled by portfolio_index AgentSession adapters.
  Use `Command.AgentSessions` for agent session management.

  ## Usage

      # Process events from portfolio AgentSession
      {:ok, result} = Command.AgentSessions.execute(:claude, session_id, input,
        event_callback: fn event ->
          # Process events in real time
        end
      )

  ## Buffering

  The normalize function supports optional buffering:
  - `:buffer` - `:tool_complete` - Buffer events until tool lifecycle completes
  - `:buffer` - `:message_complete` - Buffer events until message completes

  ## Telemetry

  Emits telemetry events for each normalized event:
  - `[:command, :stream, :event]` - Per-event metrics
  """

  @doc """
  Transforms a stream of events with optional buffering and telemetry.

  ## Arguments

  - `provider` - `:claude` or `:codex`
  - `event_stream` - Enumerable of events (from portfolio adapters or any source)
  - `opts` - Keyword list of options:
    - `:buffer` - Optional buffering strategy (`:tool_complete` or `:message_complete`)

  ## Returns

  A stream of events with buffering and telemetry applied.

  ## Raises

  - `ArgumentError` - If provider is unknown
  """
  @spec normalize(:claude | :codex, Enumerable.t(), keyword()) :: Enumerable.t(Command.Event.t())
  def normalize(provider, event_stream, opts \\ []) do
    validate_provider!(provider)

    event_stream
    |> maybe_buffer_events(opts)
    |> emit_telemetry_events()
  end

  defp validate_provider!(:claude), do: :ok
  defp validate_provider!(:codex), do: :ok

  defp validate_provider!(unknown) do
    raise ArgumentError, "Unknown provider: #{inspect(unknown)}"
  end

  # Applies optional buffering strategies
  defp maybe_buffer_events(stream, opts) do
    case Keyword.get(opts, :buffer) do
      nil -> stream
      :tool_complete -> buffer_until_tool_complete(stream)
      :message_complete -> buffer_until_message_complete(stream)
    end
  end

  # Buffers events until a tool use lifecycle completes
  defp buffer_until_tool_complete(stream) do
    stream
    |> Stream.transform([], fn
      %{type: :tool_use_start} = event, buffer ->
        {[], [event | buffer]}

      %{type: :tool_use_end} = event, buffer ->
        events = Enum.reverse([event | buffer])
        {events, []}

      event, [] ->
        {[event], []}

      event, buffer ->
        {[], [event | buffer]}
    end)
  end

  # Buffers events until a message completes
  defp buffer_until_message_complete(stream) do
    stream
    |> Stream.chunk_while(
      [],
      fn
        %{type: :message_stop} = event, acc ->
          {:cont, Enum.reverse([event | acc]), []}

        event, acc ->
          {:cont, [event | acc]}
      end,
      fn
        [] -> {:cont, []}
        acc -> {:cont, Enum.reverse(acc), []}
      end
    )
    |> Stream.flat_map(& &1)
  end

  # Emits telemetry for each event
  defp emit_telemetry_events(stream) do
    Stream.each(stream, fn event ->
      :telemetry.execute(
        [:command, :stream, :event],
        %{count: 1},
        %{type: event.type, provider: event.provider}
      )
    end)
  end
end
