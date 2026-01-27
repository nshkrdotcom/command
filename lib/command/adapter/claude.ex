defmodule Command.Adapter.Claude do
  @moduledoc """
  Normalizes Claude Agent SDK events to Command.Event schema.

  Handles the following Claude event types:
  - `message_start` - Start of message
  - `content_block_start` - Start of content block (text or tool_use)
  - `content_block_delta` - Incremental content (text_delta or input_json_delta)
  - `content_block_stop` - End of content block
  - `message_delta` - Message metadata updates (usage)
  - `message_stop` - End of message
  - `error` - Error events

  ## State Management

  The adapter maintains state across streaming events to:
  - Track session/run/prompt IDs
  - Accumulate tool input JSON fragments
  - Maintain event sequence numbers
  - Store normalization mode

  ## Tool Input Accumulation

  Claude streams tool inputs as JSON fragments. The adapter:
  1. Emits `:tool_use_start` when `content_block_start` with `tool_use` is received
  2. Accumulates JSON fragments from `input_json_delta` events
  3. Emits `:tool_use_end` with parsed input when `content_block_stop` is received

  ## Error Mapping

  Claude errors are mapped to normalized categories:
  - `overloaded_error` → `:rate_limit` (recoverable)
  - `api_error` → `:api_error` (recoverable)
  - `authentication_error` → `:auth_error` (not recoverable)
  - `invalid_request_error` → `:invalid_request` (not recoverable)
  """

  @behaviour Command.Adapter

  alias Command.Adapter.Validation
  alias Command.Event

  defstruct [
    :session_id,
    :run_id,
    :prompt_id,
    :sequence,
    :tool_inputs,
    :mode
  ]

  @impl true
  def normalize_stream(raw_stream, opts \\ []) do
    mode = Keyword.get(opts, :mode, :compatibility)
    prompt_id = Keyword.get(opts, :prompt_id, generate_uuid())

    initial_state = %__MODULE__{
      sequence: 0,
      tool_inputs: %{},
      prompt_id: prompt_id,
      mode: mode
    }

    raw_stream
    |> Stream.transform(initial_state, &normalize_event/2)
    |> Stream.flat_map(&List.wrap/1)
  end

  @impl true
  def normalize_event(event, state), do: do_normalize_event(event, state)

  @impl true
  def supports_event?(%{"type" => type}) when is_binary(type), do: true
  def supports_event?(_), do: false

  # message_start
  defp do_normalize_event(%{"type" => "message_start"} = event, state) do
    message = event["message"] || %{}
    session_id = event["session_id"] || state.session_id
    run_id = message["id"]

    normalized = %Event{
      type: :message_start,
      provider: :claude,
      session_id: handle_required(session_id, :session_id, state.mode),
      run_id: handle_required(run_id, :run_id, state.mode),
      prompt_id: state.prompt_id,
      event_id: run_id || generate_uuid(),
      sequence: state.sequence,
      timestamp: DateTime.utc_now(),
      data: %{
        message_id: run_id,
        model: message["model"],
        role: :assistant
      },
      raw: event
    }

    new_state = %{
      state
      | session_id: session_id || handle_required(nil, :session_id, state.mode),
        run_id: run_id || handle_required(nil, :run_id, state.mode),
        sequence: state.sequence + 1
    }

    {[validated(normalized, state.mode)], new_state}
  end

  # content_block_start - text
  defp do_normalize_event(
         %{
           "type" => "content_block_start",
           "content_block" => %{"type" => "text"} = block,
           "index" => index
         },
         state
       ) do
    normalized = %Event{
      type: :text_delta,
      provider: :claude,
      session_id: state.session_id,
      run_id: state.run_id,
      prompt_id: state.prompt_id,
      event_id: block["id"] || generate_uuid(),
      sequence: state.sequence,
      timestamp: DateTime.utc_now(),
      data: %{
        content: block["text"] || "",
        content_block_index: index
      },
      raw: block
    }

    {[validated(normalized, state.mode)], inc_seq(state)}
  end

  # content_block_delta - text
  defp do_normalize_event(
         %{
           "type" => "content_block_delta",
           "delta" => %{"type" => "text_delta", "text" => text},
           "index" => index
         },
         state
       ) do
    normalized = %Event{
      type: :text_delta,
      provider: :claude,
      session_id: state.session_id,
      run_id: state.run_id,
      prompt_id: state.prompt_id,
      event_id: generate_uuid(),
      sequence: state.sequence,
      timestamp: DateTime.utc_now(),
      data: %{
        content: text,
        content_block_index: index
      },
      raw: %{text: text, index: index}
    }

    {[validated(normalized, state.mode)], inc_seq(state)}
  end

  # content_block_start - tool_use
  defp do_normalize_event(
         %{
           "type" => "content_block_start",
           "content_block" => %{"type" => "tool_use"} = block
         },
         state
       ) do
    tool_use_id = block["id"]

    normalized = %Event{
      type: :tool_use_start,
      provider: :claude,
      session_id: state.session_id,
      run_id: state.run_id,
      prompt_id: state.prompt_id,
      event_id: tool_use_id || generate_uuid(),
      sequence: state.sequence,
      timestamp: DateTime.utc_now(),
      data: %{
        tool_use_id: tool_use_id,
        tool_name: block["name"],
        input_partial: nil
      },
      raw: block
    }

    new_state = %{
      state
      | tool_inputs: Map.put(state.tool_inputs, tool_use_id, ""),
        sequence: state.sequence + 1
    }

    {[validated(normalized, state.mode)], new_state}
  end

  # content_block_delta - tool_use (input_json_delta)
  defp do_normalize_event(
         %{
           "type" => "content_block_delta",
           "delta" => %{"type" => "input_json_delta", "partial_json" => json}
         },
         state
       )
       when is_binary(json) do
    # Find the active tool_use_id (last one started)
    tool_use_id = state.tool_inputs |> Map.keys() |> List.last()

    normalized = %Event{
      type: :tool_use_delta,
      provider: :claude,
      session_id: state.session_id,
      run_id: state.run_id,
      prompt_id: state.prompt_id,
      event_id: generate_uuid(),
      sequence: state.sequence,
      timestamp: DateTime.utc_now(),
      data: %{
        tool_use_id: tool_use_id,
        input_delta: json
      },
      raw: %{partial_json: json}
    }

    # Accumulate JSON for final parsing
    new_state = %{
      state
      | tool_inputs: Map.update(state.tool_inputs, tool_use_id, json, &(&1 <> json)),
        sequence: state.sequence + 1
    }

    {[validated(normalized, state.mode)], new_state}
  end

  # content_block_stop (for tool_use)
  defp do_normalize_event(
         %{"type" => "content_block_stop", "index" => _index},
         state
       )
       when map_size(state.tool_inputs) > 0 do
    # Complete the most recent tool_use
    {tool_use_id, accumulated_json} =
      Enum.max_by(state.tool_inputs, fn {_k, v} ->
        String.length(v)
      end)

    input =
      case Jason.decode(accumulated_json) do
        {:ok, parsed} -> parsed
        {:error, _} -> %{"_raw" => accumulated_json}
      end

    normalized = %Event{
      type: :tool_use_end,
      provider: :claude,
      session_id: state.session_id,
      run_id: state.run_id,
      prompt_id: state.prompt_id,
      event_id: generate_uuid(),
      sequence: state.sequence,
      timestamp: DateTime.utc_now(),
      data: %{
        tool_use_id: tool_use_id,
        tool_name: nil,
        # Name was in start event
        input: input
      },
      raw: %{accumulated_json: accumulated_json}
    }

    new_state = %{
      state
      | tool_inputs: Map.delete(state.tool_inputs, tool_use_id),
        sequence: state.sequence + 1
    }

    {[validated(normalized, state.mode)], new_state}
  end

  # content_block_start - thinking
  defp do_normalize_event(
         %{
           "type" => "content_block_start",
           "content_block" => %{"type" => "thinking"} = block
         },
         state
       ) do
    normalized = %Event{
      type: :reasoning,
      provider: :claude,
      session_id: state.session_id,
      run_id: state.run_id,
      prompt_id: state.prompt_id,
      event_id: block["id"] || generate_uuid(),
      sequence: state.sequence,
      timestamp: DateTime.utc_now(),
      data: %{
        text: block["thinking"] || "",
        summary: nil
      },
      raw: block
    }

    {[validated(normalized, state.mode)], inc_seq(state)}
  end

  # message_delta (contains usage)
  defp do_normalize_event(
         %{"type" => "message_delta", "usage" => usage},
         state
       )
       when is_map(usage) do
    normalized = %Event{
      type: :usage_update,
      provider: :claude,
      session_id: state.session_id,
      run_id: state.run_id,
      prompt_id: state.prompt_id,
      event_id: generate_uuid(),
      sequence: state.sequence,
      timestamp: DateTime.utc_now(),
      data: %{
        input_tokens: usage["input_tokens"] || 0,
        output_tokens: usage["output_tokens"] || 0,
        cache_read_tokens: usage["cache_read_input_tokens"],
        cache_write_tokens: usage["cache_creation_input_tokens"],
        cost_usd: nil
      },
      raw: usage
    }

    {[validated(normalized, state.mode)], inc_seq(state)}
  end

  # message_stop
  defp do_normalize_event(%{"type" => "message_stop"} = event, state) do
    stop_reason =
      case event["stop_reason"] do
        "end_turn" -> :end_turn
        "tool_use" -> :tool_use
        "max_tokens" -> :max_tokens
        "stop_sequence" -> :stop_sequence
        _ -> :end_turn
      end

    normalized = %Event{
      type: :message_stop,
      provider: :claude,
      session_id: state.session_id,
      run_id: state.run_id,
      prompt_id: state.prompt_id,
      event_id: generate_uuid(),
      sequence: state.sequence,
      timestamp: DateTime.utc_now(),
      data: %{
        stop_reason: stop_reason
      },
      raw: event
    }

    {[validated(normalized, state.mode)], inc_seq(state)}
  end

  # error
  defp do_normalize_event(%{"type" => "error", "error" => error}, state) do
    normalized = %Event{
      type: :error,
      provider: :claude,
      session_id: state.session_id,
      run_id: state.run_id,
      prompt_id: state.prompt_id,
      event_id: generate_uuid(),
      sequence: state.sequence,
      timestamp: DateTime.utc_now(),
      data: normalize_claude_error(error),
      raw: error
    }

    {[validated(normalized, state.mode)], inc_seq(state)}
  end

  # content_block_stop (non-tool)
  defp do_normalize_event(%{"type" => "content_block_stop"}, state) do
    # Non-tool content block stops don't produce events
    {[], state}
  end

  # message_delta (no usage)
  defp do_normalize_event(%{"type" => "message_delta"}, state) do
    # Message deltas without usage don't produce events
    {[], state}
  end

  # Fallback for unrecognized events
  defp do_normalize_event(event, state) do
    event_type = event["type"] || event[:type] || "unknown"

    normalized = %Event{
      type: :raw,
      provider: :claude,
      session_id: state.session_id,
      run_id: state.run_id,
      prompt_id: state.prompt_id,
      event_id: generate_uuid(),
      sequence: state.sequence,
      timestamp: DateTime.utc_now(),
      data: %{
        original_type: event_type,
        payload: event
      },
      raw: event
    }

    emit_telemetry(:unknown_event, %{type: event_type, provider: :claude})
    {[validated(normalized, state.mode)], inc_seq(state)}
  end

  # Helper functions

  defp normalize_claude_error(error) do
    %{
      error_type: categorize_claude_error(error),
      message: error["message"] || inspect(error),
      code: error["type"],
      recoverable: recoverable_claude_error?(error),
      retry_after_ms: nil
    }
  end

  defp categorize_claude_error(%{"type" => "overloaded_error"}), do: :rate_limit
  defp categorize_claude_error(%{"type" => "api_error"}), do: :api_error
  defp categorize_claude_error(%{"type" => "authentication_error"}), do: :auth_error
  defp categorize_claude_error(%{"type" => "invalid_request_error"}), do: :invalid_request
  defp categorize_claude_error(_), do: :unknown

  defp recoverable_claude_error?(%{"type" => "overloaded_error"}), do: true
  defp recoverable_claude_error?(%{"type" => "api_error"}), do: true
  defp recoverable_claude_error?(_), do: false

  defp handle_required(value, _field, _mode) when not is_nil(value), do: value

  defp handle_required(nil, field, :compatibility) do
    emit_telemetry(:fallback_used, %{field: field})
    generate_uuid()
  end

  defp handle_required(nil, field, :strict) do
    raise ArgumentError, "Missing required field: #{field}"
  end

  defp inc_seq(state), do: %{state | sequence: state.sequence + 1}

  defp validated(event, :strict), do: Validation.validate!(event)
  defp validated(event, :compatibility), do: event

  defp generate_uuid do
    # Simple UUID v4 implementation
    <<a::48, _::4, b::12, _::2, c::62>> = :crypto.strong_rand_bytes(16)

    <<a::48, 4::4, b::12, 2::2, c::62>>
    |> Base.encode16(case: :lower)
    |> String.replace(~r/(.{8})(.{4})(.{4})(.{4})(.{12})/, "\\1-\\2-\\3-\\4-\\5")
  end

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:command, :adapter, :claude, event],
      %{count: 1},
      metadata
    )
  end
end
