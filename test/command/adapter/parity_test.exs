defmodule Command.Adapter.ParityTest do
  use ExUnit.Case, async: true

  alias Command.Adapter.{Claude, Codex}

  @moduledoc false

  # Mock Codex event structs for testing
  defmodule CodexEvents do
    defmodule ThreadStarted do
      defstruct [:thread_id, :metadata]
    end

    defmodule TurnStarted do
      defstruct [:thread_id, :turn_id]
    end

    defmodule TurnCompleted do
      defstruct [:thread_id, :turn_id, :status, :response_id, :usage]
    end

    defmodule TurnFailed do
      defstruct [:thread_id, :turn_id, :error]
    end
  end

  defmodule CodexItems do
    defmodule AgentMessage do
      defstruct [:id, :text]
    end

    defmodule Reasoning do
      defstruct [:id, :text, :summary]
    end
  end

  describe "text_delta event parity" do
    test "both providers produce text_delta events with identical data keys" do
      claude_event = build_claude_text_delta()
      codex_event = build_codex_text_delta()

      assert_field_parity(claude_event, codex_event, [:type, :data])
      assert claude_event.type == :text_delta
      assert codex_event.type == :text_delta

      # Data must have same keys
      claude_keys = Map.keys(claude_event.data) |> Enum.sort()
      codex_keys = Map.keys(codex_event.data) |> Enum.sort()
      assert claude_keys == codex_keys
    end

    test "text_delta data contains required fields" do
      claude_event = build_claude_text_delta()
      codex_event = build_codex_text_delta()

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
      claude_event = build_claude_message_start()
      codex_event = build_codex_message_start()

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
      claude_event = build_claude_message_stop()
      codex_event = build_codex_message_stop()

      assert claude_event.type == :message_stop
      assert codex_event.type == :message_stop

      for event <- [claude_event, codex_event] do
        assert Map.has_key?(event.data, :stop_reason)
      end
    end
  end

  describe "error event parity" do
    test "both providers produce error events with identical data keys" do
      claude_event = build_claude_error()
      codex_event = build_codex_error()

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
      claude_event = build_claude_error()
      codex_event = build_codex_error()

      for event <- [claude_event, codex_event] do
        assert is_atom(event.data.error_type)
        assert is_binary(event.data.message)
        assert is_boolean(event.data.recoverable)
      end
    end
  end

  describe "usage_update event parity" do
    test "both providers produce usage_update events with identical data keys" do
      claude_event = build_claude_usage()
      codex_event = build_codex_usage()

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
      claude_event = build_claude_usage()
      codex_event = build_codex_usage()

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
      claude_event = build_claude_reasoning()
      codex_event = build_codex_reasoning()

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

      claude_stop = build_claude_message_stop()
      codex_stop = build_codex_message_stop()

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

      claude_error = build_claude_error()
      codex_error = build_codex_error()

      assert claude_error.data.error_type in valid_error_types
      assert codex_error.data.error_type in valid_error_types
    end
  end

  describe "identity field parity" do
    test "both providers populate identity fields" do
      claude_events = build_claude_full_stream()
      codex_events = build_codex_full_stream()

      for event <- claude_events ++ codex_events do
        assert is_atom(event.type)
        assert event.provider in [:claude, :codex]
        assert is_binary(event.event_id) or is_nil(event.event_id)
        assert is_integer(event.sequence)
        assert %DateTime{} = event.timestamp
      end
    end

    test "sequence numbers are monotonically increasing per provider" do
      claude_events = build_claude_full_stream()
      codex_events = build_codex_full_stream()

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

  # Build Claude events via the adapter
  defp build_claude_text_delta do
    [
      %{"type" => "message_start", "message" => %{"id" => "m1"}, "session_id" => "s1"},
      %{
        "type" => "content_block_delta",
        "delta" => %{"type" => "text_delta", "text" => "Hi"},
        "index" => 0
      }
    ]
    |> to_stream()
    |> Claude.normalize_stream(mode: :compatibility)
    |> Enum.find(&(&1.type == :text_delta))
  end

  defp build_claude_message_start do
    [
      %{
        "type" => "message_start",
        "message" => %{"id" => "m1", "model" => "claude-sonnet-4"},
        "session_id" => "s1"
      }
    ]
    |> to_stream()
    |> Claude.normalize_stream(mode: :compatibility)
    |> Enum.find(&(&1.type == :message_start))
  end

  defp build_claude_message_stop do
    [
      %{"type" => "message_start", "message" => %{"id" => "m1"}, "session_id" => "s1"},
      %{"type" => "message_stop", "stop_reason" => "end_turn"}
    ]
    |> to_stream()
    |> Claude.normalize_stream(mode: :compatibility)
    |> Enum.find(&(&1.type == :message_stop))
  end

  defp build_claude_error do
    [
      %{
        "type" => "error",
        "error" => %{"type" => "overloaded_error", "message" => "Server overloaded"}
      }
    ]
    |> to_stream()
    |> Claude.normalize_stream(mode: :compatibility)
    |> Enum.find(&(&1.type == :error))
  end

  defp build_claude_usage do
    [
      %{"type" => "message_start", "message" => %{"id" => "m1"}, "session_id" => "s1"},
      %{
        "type" => "message_delta",
        "usage" => %{"input_tokens" => 100, "output_tokens" => 50}
      }
    ]
    |> to_stream()
    |> Claude.normalize_stream(mode: :compatibility)
    |> Enum.find(&(&1.type == :usage_update))
  end

  defp build_claude_reasoning do
    [
      %{"type" => "message_start", "message" => %{"id" => "m1"}, "session_id" => "s1"},
      %{
        "type" => "content_block_start",
        "content_block" => %{"type" => "thinking", "thinking" => "Let me think..."},
        "index" => 0
      }
    ]
    |> to_stream()
    |> Claude.normalize_stream(mode: :compatibility)
    |> Enum.find(&(&1.type == :reasoning))
  end

  defp build_claude_full_stream do
    [
      %{"type" => "message_start", "message" => %{"id" => "m1"}, "session_id" => "s1"},
      %{
        "type" => "content_block_delta",
        "delta" => %{"type" => "text_delta", "text" => "Hello"},
        "index" => 0
      },
      %{
        "type" => "message_delta",
        "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
      },
      %{"type" => "message_stop", "stop_reason" => "end_turn"}
    ]
    |> to_stream()
    |> Claude.normalize_stream(mode: :compatibility)
    |> Enum.to_list()
  end

  # Build Codex events via the adapter
  defp build_codex_text_delta do
    [
      %CodexEvents.TurnStarted{thread_id: "t1", turn_id: "turn_1"},
      %CodexItems.AgentMessage{id: "m1", text: "Hi"}
    ]
    |> to_stream()
    |> Codex.normalize_stream(mode: :compatibility)
    |> Enum.find(&(&1.type == :text_delta))
  end

  defp build_codex_message_start do
    [
      %CodexEvents.ThreadStarted{
        thread_id: "thread_1",
        metadata: %{model: "gpt-4.1"}
      }
    ]
    |> to_stream()
    |> Codex.normalize_stream(mode: :compatibility)
    |> Enum.find(&(&1.type == :message_start))
  end

  defp build_codex_message_stop do
    [
      %CodexEvents.TurnStarted{thread_id: "t1", turn_id: "turn_1"},
      %CodexEvents.TurnCompleted{
        thread_id: "t1",
        turn_id: "turn_1",
        status: "completed",
        response_id: "resp_1",
        usage: nil
      }
    ]
    |> to_stream()
    |> Codex.normalize_stream(mode: :compatibility)
    |> Enum.find(&(&1.type == :message_stop))
  end

  defp build_codex_error do
    [
      %CodexEvents.TurnFailed{
        thread_id: "t1",
        turn_id: "turn_1",
        error: %{kind: :rate_limit, message: "Rate limited"}
      }
    ]
    |> to_stream()
    |> Codex.normalize_stream(mode: :compatibility)
    |> Enum.find(&(&1.type == :error))
  end

  defp build_codex_usage do
    [
      %CodexEvents.TurnStarted{thread_id: "t1", turn_id: "turn_1"},
      %CodexEvents.TurnCompleted{
        thread_id: "t1",
        turn_id: "turn_1",
        status: "completed",
        response_id: "resp_1",
        usage: %{input_tokens: 200, output_tokens: 100}
      }
    ]
    |> to_stream()
    |> Codex.normalize_stream(mode: :compatibility)
    |> Enum.find(&(&1.type == :usage_update))
  end

  defp build_codex_reasoning do
    [
      %CodexEvents.TurnStarted{thread_id: "t1", turn_id: "turn_1"},
      %CodexItems.Reasoning{id: "r1", text: "Thinking...", summary: ["Step 1"]}
    ]
    |> to_stream()
    |> Codex.normalize_stream(mode: :compatibility)
    |> Enum.find(&(&1.type == :reasoning))
  end

  defp build_codex_full_stream do
    [
      %CodexEvents.TurnStarted{thread_id: "t1", turn_id: "turn_1"},
      %CodexItems.AgentMessage{id: "m1", text: "Hello"},
      %CodexEvents.TurnCompleted{
        thread_id: "t1",
        turn_id: "turn_1",
        status: "completed",
        response_id: "resp_1",
        usage: %{input_tokens: 10, output_tokens: 5}
      }
    ]
    |> to_stream()
    |> Codex.normalize_stream(mode: :compatibility)
    |> Enum.to_list()
  end

  defp to_stream(list), do: Stream.into(list, [])
end
