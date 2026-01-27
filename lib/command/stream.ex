defmodule Command.Stream do
  @moduledoc """
  Unified stream handling for multi-provider agent interactions.

  This module provides the primary entry point for normalizing provider-specific
  event streams into the unified `Command.Event` schema. It routes streams to
  the appropriate adapter and handles common stream transformations.

  ## Usage

      # Normalize Claude stream
      raw_claude_stream
      |> Command.Stream.normalize(:claude, mode: :strict, context: %{
        run_id: "run-123",
        session_id: "session-456"
      })
      |> Enum.each(&process_event/1)

      # Normalize Codex stream
      raw_codex_stream
      |> Command.Stream.normalize(:codex, mode: :compatibility)
      |> Enum.to_list()

  ## Buffering

  The normalize function supports optional buffering:
  - `:buffer` - `:tool_complete` - Buffer events until tool lifecycle completes
  - `:buffer` - `:message_complete` - Buffer events until message completes

  ## Telemetry

  Emits telemetry events for each normalized event:
  - `[:command, :stream, :event]` - Per-event metrics
  """

  alias Command.Adapter

  @doc """
  Normalizes a provider-specific event stream to `Command.Event` structs.

  ## Arguments

  - `provider` - `:claude` or `:codex`
  - `raw_stream` - Enumerable of provider-specific events
  - `opts` - Keyword list of options:
    - `:mode` - `:strict` or `:compatibility` (defaults based on environment)
    - `:prompt_id` - UUID for the prompt (generated if not provided)
    - `:context` - Map with `run_id` and `session_id` (required for strict mode)
    - `:buffer` - Optional buffering strategy (`:tool_complete` or `:message_complete`)

  ## Returns

  A stream of `Command.Event` structs.

  ## Raises

  - `ArgumentError` - If provider is unknown

  ## Examples

      # Basic normalization
      events = Command.Stream.normalize(:claude, raw_events)

      # Strict mode with context
      events = Command.Stream.normalize(:claude, raw_events,
        mode: :strict,
        context: %{run_id: "run-1", session_id: "session-1"}
      )

      # With buffering
      events = Command.Stream.normalize(:codex, raw_events,
        buffer: :tool_complete
      )
  """
  @spec normalize(:claude | :codex, Enumerable.t(), keyword()) :: Enumerable.t(Command.Event.t())
  def normalize(provider, raw_stream, opts \\ []) do
    adapter = adapter_for(provider)
    mode = Adapter.select_mode(opts)

    raw_stream
    |> adapter.normalize_stream(Keyword.put(opts, :mode, mode))
    |> maybe_buffer_events(opts)
    |> emit_telemetry_events()
  end

  # Routes to the appropriate adapter module
  defp adapter_for(:claude), do: Command.Adapter.Claude
  defp adapter_for(:codex), do: Command.Adapter.Codex

  defp adapter_for(unknown) do
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
