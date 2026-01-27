defmodule Command.Adapter.ParityTest do
  use ExUnit.Case, async: true

  alias Command.Event

  @moduledoc false

  # This test verifies that the Command.Event schema supports consistent
  # event structures across providers. Event normalization is now handled
  # by portfolio_index AgentSession adapters, but the schema must still
  # support the same data shapes for both Claude and Codex events.

  describe "text_delta event parity" do
    test "both providers produce text_delta events with identical data keys" do
      claude_event = build_text_delta(:claude)
      codex_event = build_text_delta(:codex)

      assert_field_parity(claude_event, codex_event, [:type, :data])
      assert claude_event.type == :text_delta
      assert codex_event.type == :text_delta

      # Data must have same keys
      claude_keys = Map.keys(claude_event.data) |> Enum.sort()
      codex_keys = Map.keys(codex_event.data) |> Enum.sort()
      assert claude_keys == codex_keys
    end

    test "text_delta data contains required fields" do
      claude_event = build_text_delta(:claude)
      codex_event = build_text_delta(:codex)

      for event <- [claude_event, codex_event] do
        assert Map.has_key?(event.data, :content)
        assert Map.has_key?(event.data, :content_block_index)
        assert is_binary(event.data.content)
        assert is_integer(event.data.content_block_index)
      end
    end
  end

  describe "message_start event parity" do
    test "both providers produce message_start events with identical data keys" do
      claude_event = build_message_start(:claude)
      codex_event = build_message_start(:codex)

      assert claude_event.type == :message_start
      assert codex_event.type == :message_start

      for event <- [claude_event, codex_event] do
        assert Map.has_key?(event.data, :message_id)
        assert Map.has_key?(event.data, :model)
        assert Map.has_key?(event.data, :role)
        assert event.data.role == :assistant
      end
    end
  end

  describe "message_stop event parity" do
    test "both providers produce message_stop events with identical data keys" do
      claude_event = build_message_stop(:claude)
      codex_event = build_message_stop(:codex)

      assert claude_event.type == :message_stop
      assert codex_event.type == :message_stop

      for event <- [claude_event, codex_event] do
        assert Map.has_key?(event.data, :stop_reason)
      end
    end
  end

  describe "error event parity" do
    test "both providers produce error events with identical data keys" do
      claude_event = build_error(:claude)
      codex_event = build_error(:codex)

      assert claude_event.type == :error
      assert codex_event.type == :error

      required_error_fields = [:error_type, :message, :recoverable]

      for field <- required_error_fields do
        assert Map.has_key?(claude_event.data, field),
               "Claude error missing field: #{field}"

        assert Map.has_key?(codex_event.data, field),
               "Codex error missing field: #{field}"
      end
    end

    test "error data fields have correct types" do
      claude_event = build_error(:claude)
      codex_event = build_error(:codex)

      for event <- [claude_event, codex_event] do
        assert is_atom(event.data.error_type)
        assert is_binary(event.data.message)
        assert is_boolean(event.data.recoverable)
      end
    end
  end

  describe "usage_update event parity" do
    test "both providers produce usage_update events with identical data keys" do
      claude_event = build_usage(:claude)
      codex_event = build_usage(:codex)

      assert claude_event.type == :usage_update
      assert codex_event.type == :usage_update

      required_usage_fields = [:input_tokens, :output_tokens]

      for field <- required_usage_fields do
        assert Map.has_key?(claude_event.data, field),
               "Claude usage missing field: #{field}"

        assert Map.has_key?(codex_event.data, field),
               "Codex usage missing field: #{field}"
      end
    end

    test "usage token counts are non-negative integers" do
      claude_event = build_usage(:claude)
      codex_event = build_usage(:codex)

      for event <- [claude_event, codex_event] do
        assert is_integer(event.data.input_tokens)
        assert is_integer(event.data.output_tokens)
        assert event.data.input_tokens >= 0
        assert event.data.output_tokens >= 0
      end
    end
  end

  describe "reasoning event parity" do
    test "both providers produce reasoning events with identical data keys" do
      claude_event = build_reasoning(:claude)
      codex_event = build_reasoning(:codex)

      assert claude_event.type == :reasoning
      assert codex_event.type == :reasoning

      for event <- [claude_event, codex_event] do
        assert Map.has_key?(event.data, :text)
        assert Map.has_key?(event.data, :summary)
        assert is_binary(event.data.text)
      end
    end
  end

  describe "stop_reason parity" do
    test "both providers normalize to same stop_reason atoms" do
      valid_stop_reasons = [:end_turn, :tool_use, :max_tokens, :stop_sequence, :error]

      claude_stop = build_message_stop(:claude)
      codex_stop = build_message_stop(:codex)

      assert claude_stop.data.stop_reason in valid_stop_reasons
      assert codex_stop.data.stop_reason in valid_stop_reasons
    end
  end

  describe "error_type parity" do
    test "both providers normalize to same error_type atoms" do
      valid_error_types = [
        :rate_limit,
        :auth_error,
        :api_error,
        :invalid_request,
        :timeout,
        :parse_error,
        :sandbox_error,
        :tool_error,
        :unknown
      ]

      claude_error = build_error(:claude)
      codex_error = build_error(:codex)

      assert claude_error.data.error_type in valid_error_types
      assert codex_error.data.error_type in valid_error_types
    end
  end

  describe "identity field parity" do
    test "both providers populate identity fields" do
      claude_events = build_full_stream(:claude)
      codex_events = build_full_stream(:codex)

      for event <- claude_events ++ codex_events do
        assert is_atom(event.type)
        assert event.provider in [:claude, :codex]
        assert is_binary(event.event_id) or is_nil(event.event_id)
        assert is_integer(event.sequence)
        assert %DateTime{} = event.timestamp
      end
    end

    test "sequence numbers are monotonically increasing per provider" do
      claude_events = build_full_stream(:claude)
      codex_events = build_full_stream(:codex)

      for events <- [claude_events, codex_events] do
        sequences = Enum.map(events, & &1.sequence)
        assert sequences == Enum.sort(sequences)
        assert Enum.uniq(sequences) == sequences
      end
    end
  end

  # Helper: assert that two events share the same fields
  defp assert_field_parity(event1, event2, fields) do
    for field <- fields do
      assert Map.has_key?(event1, field), "Event 1 missing field: #{field}"
      assert Map.has_key?(event2, field), "Event 2 missing field: #{field}"
    end
  end

  # Build events directly as Command.Event structs
  # (Event normalization is now done by portfolio_index adapters)

  defp build_event(type, provider, data, opts \\ []) do
    %Event{
      type: type,
      provider: provider,
      session_id: Keyword.get(opts, :session_id, "session-1"),
      run_id: Keyword.get(opts, :run_id, "run-1"),
      prompt_id: Keyword.get(opts, :prompt_id, "prompt-1"),
      event_id: Keyword.get(opts, :event_id, "event-#{:erlang.unique_integer([:positive])}"),
      sequence: Keyword.get(opts, :sequence, 0),
      timestamp: DateTime.utc_now(),
      data: data,
      raw: %{}
    }
  end

  defp build_text_delta(provider) do
    build_event(
      :text_delta,
      provider,
      %{
        content: "Hello",
        content_block_index: 0
      },
      sequence: 1
    )
  end

  defp build_message_start(provider) do
    model = if provider == :claude, do: "claude-sonnet-4", else: "gpt-4.1"

    build_event(
      :message_start,
      provider,
      %{
        message_id: "msg-1",
        model: model,
        role: :assistant
      },
      sequence: 0
    )
  end

  defp build_message_stop(provider) do
    build_event(
      :message_stop,
      provider,
      %{
        stop_reason: :end_turn
      },
      sequence: 3
    )
  end

  defp build_error(provider) do
    build_event(:error, provider, %{
      error_type: :rate_limit,
      message: "Rate limited",
      code: nil,
      recoverable: true,
      retry_after_ms: nil
    })
  end

  defp build_usage(provider) do
    build_event(
      :usage_update,
      provider,
      %{
        input_tokens: 100,
        output_tokens: 50,
        cache_read_tokens: nil,
        cache_write_tokens: nil,
        cost_usd: nil
      },
      sequence: 2
    )
  end

  defp build_reasoning(provider) do
    build_event(
      :reasoning,
      provider,
      %{
        text: "Let me think...",
        summary: nil
      },
      sequence: 1
    )
  end

  defp build_full_stream(provider) do
    [
      build_message_start(provider),
      build_text_delta(provider),
      build_usage(provider),
      build_message_stop(provider)
    ]
  end
end
