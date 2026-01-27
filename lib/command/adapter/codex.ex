defmodule Command.Adapter.Codex do
  @moduledoc """
  Normalizes Codex SDK events to Command.Event schema.

  Handles the following Codex event types:
  - `ThreadStarted` - Thread initialization
  - `TurnStarted` - Turn begins
  - `TurnCompleted` - Turn ends successfully
  - `TurnFailed` - Turn fails with error
  - `AgentMessage` - Text message item
  - `Reasoning` - Reasoning/thinking item
  - `FileChange` - File modification item
  - `CommandExecution` - Shell command item
  - `McpToolCall` - MCP tool invocation

  ## State Management

  The adapter maintains state across streaming events to:
  - Track thread/turn IDs (mapped to session/run)
  - Maintain event sequence numbers
  - Store normalization mode

  ## Event vs Item Mapping

  Codex distinguishes between Events (lifecycle) and Items (content):
  - Events → `:message_start`, `:message_stop`, `:error`
  - Items → `:text_delta`, `:reasoning`, `:file_change`, etc.

  ## Error Mapping

  Codex errors are mapped to normalized categories:
  - `:rate_limit` → `:rate_limit` (recoverable)
  - `:sandbox_assessment_failed` → `:sandbox_error` (not recoverable)
  - `:timeout` → `:timeout` (recoverable)
  """

  @behaviour Command.Adapter

  alias Command.Adapter.Validation
  alias Command.Event

  defstruct [
    :session_id,
    :run_id,
    :prompt_id,
    :sequence,
    :mode
  ]

  @impl true
  def normalize_stream(raw_stream, opts \\ []) do
    mode = Keyword.get(opts, :mode, :compatibility)
    prompt_id = Keyword.get(opts, :prompt_id, generate_uuid())

    initial_state = %__MODULE__{
      sequence: 0,
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
  def supports_event?(%_{} = _struct), do: true
  def supports_event?(_), do: false

  # ThreadStarted
  defp do_normalize_event(%{__struct__: mod, thread_id: thread_id} = event, state) do
    case extract_module_name(mod) do
      "ThreadStarted" ->
        do_normalize_thread_started(event, thread_id, state)

      "TurnStarted" ->
        turn_id = Map.get(event, :turn_id)
        do_normalize_turn_started(event, thread_id, turn_id, state)

      "AgentMessage" ->
        id = Map.get(event, :id)
        text = Map.get(event, :text)
        do_normalize_agent_message(event, id, text, state)

      "Reasoning" ->
        id = Map.get(event, :id)
        text = Map.get(event, :text)
        do_normalize_reasoning(event, id, text, state)

      "TurnCompleted" ->
        turn_id = Map.get(event, :turn_id)
        status = Map.get(event, :status)
        do_normalize_turn_completed(event, thread_id, turn_id, status, state)

      "TurnFailed" ->
        turn_id = Map.get(event, :turn_id)
        error = Map.get(event, :error)
        do_normalize_turn_failed(event, thread_id, turn_id, error, state)

      _ ->
        # Fall through to generic handler
        do_normalize_unknown(event, state)
    end
  end

  # Handle struct-based items without thread_id (AgentMessage, Reasoning, etc.)
  defp do_normalize_event(%{__struct__: mod} = event, state) do
    case extract_module_name(mod) do
      "AgentMessage" ->
        id = Map.get(event, :id)
        text = Map.get(event, :text)
        do_normalize_agent_message(event, id, text, state)

      "Reasoning" ->
        id = Map.get(event, :id)
        text = Map.get(event, :text)
        do_normalize_reasoning(event, id, text, state)

      _ ->
        do_normalize_unknown(event, state)
    end
  end

  # Handle non-struct events
  defp do_normalize_event(event, state) do
    do_normalize_unknown(event, state)
  end

  defp do_normalize_thread_started(event, thread_id, state) do
    metadata = Map.get(event, :metadata, %{})

    normalized = %Event{
      type: :message_start,
      provider: :codex,
      session_id: thread_id,
      run_id: nil,
      prompt_id: state.prompt_id,
      event_id: thread_id,
      sequence: state.sequence,
      timestamp: DateTime.utc_now(),
      data: %{
        message_id: thread_id,
        model: metadata[:model],
        role: :assistant
      },
      raw: event
    }

    new_state = %{
      state
      | session_id: thread_id,
        sequence: state.sequence + 1
    }

    {[validated(normalized, state.mode)], new_state}
  end

  defp do_normalize_turn_started(event, thread_id, turn_id, state) do
    normalized = %Event{
      type: :message_start,
      provider: :codex,
      session_id: thread_id,
      run_id: turn_id,
      prompt_id: state.prompt_id,
      event_id: turn_id,
      sequence: state.sequence,
      timestamp: DateTime.utc_now(),
      data: %{
        message_id: turn_id,
        model: nil,
        role: :assistant
      },
      raw: event
    }

    new_state = %{
      state
      | session_id: thread_id,
        run_id: turn_id,
        sequence: state.sequence + 1
    }

    {[validated(normalized, state.mode)], new_state}
  end

  defp do_normalize_agent_message(item, id, text, state) do
    normalized = %Event{
      type: :text_delta,
      provider: :codex,
      session_id: state.session_id,
      run_id: state.run_id,
      prompt_id: state.prompt_id,
      event_id: id,
      sequence: state.sequence,
      timestamp: DateTime.utc_now(),
      data: %{
        content: text,
        content_block_index: 0
      },
      raw: item
    }

    {[validated(normalized, state.mode)], inc_seq(state)}
  end

  defp do_normalize_reasoning(item, id, text, state) do
    summary =
      case Map.get(item, :summary) do
        list when is_list(list) -> Enum.join(list, "\n")
        text when is_binary(text) -> text
        _ -> nil
      end

    normalized = %Event{
      type: :reasoning,
      provider: :codex,
      session_id: state.session_id,
      run_id: state.run_id,
      prompt_id: state.prompt_id,
      event_id: id,
      sequence: state.sequence,
      timestamp: DateTime.utc_now(),
      data: %{
        text: text,
        summary: summary
      },
      raw: item
    }

    {[validated(normalized, state.mode)], inc_seq(state)}
  end

  defp do_normalize_turn_completed(event, thread_id, turn_id, status, state) do
    stop_reason = normalize_stop_reason(status)
    usage = Map.get(event, :usage)
    usage_event = maybe_build_usage_event(usage, thread_id, turn_id, state)

    stop_event = %Event{
      type: :message_stop,
      provider: :codex,
      session_id: thread_id,
      run_id: turn_id,
      prompt_id: state.prompt_id,
      event_id: Map.get(event, :response_id) || generate_uuid(),
      sequence: state.sequence + if(usage_event, do: 1, else: 0),
      timestamp: DateTime.utc_now(),
      data: %{
        stop_reason: stop_reason
      },
      raw: event
    }

    events =
      if usage_event do
        [validated(usage_event, state.mode), validated(stop_event, state.mode)]
      else
        [validated(stop_event, state.mode)]
      end

    new_state = %{state | sequence: state.sequence + length(events)}
    {events, new_state}
  end

  defp normalize_stop_reason("completed"), do: :end_turn
  defp normalize_stop_reason("tool_use"), do: :tool_use
  defp normalize_stop_reason("max_tokens"), do: :max_tokens
  defp normalize_stop_reason(_), do: :end_turn

  defp maybe_build_usage_event(nil, _thread_id, _turn_id, _state), do: nil

  defp maybe_build_usage_event(usage, thread_id, turn_id, state) do
    %Event{
      type: :usage_update,
      provider: :codex,
      session_id: thread_id,
      run_id: turn_id,
      prompt_id: state.prompt_id,
      event_id: generate_uuid(),
      sequence: state.sequence,
      timestamp: DateTime.utc_now(),
      data: %{
        input_tokens: usage[:input_tokens] || usage["input_tokens"] || 0,
        output_tokens: usage[:output_tokens] || usage["output_tokens"] || 0,
        cache_read_tokens: nil,
        cache_write_tokens: nil,
        cost_usd: nil
      },
      raw: usage
    }
  end

  defp do_normalize_turn_failed(event, thread_id, turn_id, error, state) do
    normalized = %Event{
      type: :error,
      provider: :codex,
      session_id: thread_id,
      run_id: turn_id,
      prompt_id: state.prompt_id,
      event_id: generate_uuid(),
      sequence: state.sequence,
      timestamp: DateTime.utc_now(),
      data: normalize_codex_error(error),
      raw: event
    }

    {[validated(normalized, state.mode)], inc_seq(state)}
  end

  defp do_normalize_unknown(event, state) do
    event_type = extract_event_type(event)

    normalized = %Event{
      type: :raw,
      provider: :codex,
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

    emit_telemetry(:unknown_event, %{type: event_type, provider: :codex})
    {[validated(normalized, state.mode)], inc_seq(state)}
  end

  # Helper functions

  defp extract_module_name(mod) when is_atom(mod) do
    mod
    |> Module.split()
    |> List.last()
  end

  defp normalize_codex_error(error) when is_map(error) do
    %{
      error_type: categorize_codex_error(error),
      message: error[:message] || error["message"] || inspect(error),
      code: error[:code] || error["code"],
      recoverable: recoverable_codex_error?(error),
      retry_after_ms: error[:retry_after_ms] || error["retry_after_ms"]
    }
  end

  defp normalize_codex_error(error) do
    %{
      error_type: :unknown,
      message: inspect(error),
      code: nil,
      recoverable: false,
      retry_after_ms: nil
    }
  end

  defp categorize_codex_error(%{kind: :rate_limit}), do: :rate_limit
  defp categorize_codex_error(%{"kind" => "rate_limit"}), do: :rate_limit
  defp categorize_codex_error(%{kind: :sandbox_assessment_failed}), do: :sandbox_error

  defp categorize_codex_error(%{"kind" => "sandbox_assessment_failed"}),
    do: :sandbox_error

  defp categorize_codex_error(%{kind: :timeout}), do: :timeout
  defp categorize_codex_error(%{"kind" => "timeout"}), do: :timeout
  defp categorize_codex_error(_), do: :unknown

  defp recoverable_codex_error?(%{kind: :rate_limit}), do: true
  defp recoverable_codex_error?(%{"kind" => "rate_limit"}), do: true
  defp recoverable_codex_error?(%{kind: :timeout}), do: true
  defp recoverable_codex_error?(%{"kind" => "timeout"}), do: true
  defp recoverable_codex_error?(%{retryable?: true}), do: true
  defp recoverable_codex_error?(_), do: false

  defp extract_event_type(%{__struct__: struct}), do: struct
  defp extract_event_type(%{type: type}), do: type
  defp extract_event_type(%{"type" => type}), do: type
  defp extract_event_type(_), do: "unknown"

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
      [:command, :adapter, :codex, event],
      %{count: 1},
      metadata
    )
  end
end
