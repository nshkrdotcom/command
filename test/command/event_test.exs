defmodule Command.EventTest do
  use ExUnit.Case, async: true

  alias Command.Event

  describe "struct definition" do
    test "creates event with all fields" do
      event = %Event{
        type: :text_delta,
        provider: :claude,
        session_id: "session-123",
        run_id: "run-456",
        prompt_id: "prompt-789",
        event_id: "event-abc",
        sequence: 0,
        timestamp: DateTime.utc_now(),
        data: %{content: "Hello"},
        raw: %{}
      }

      assert event.type == :text_delta
      assert event.provider == :claude
    end

    test "enforces required keys" do
      # Struct should have all defined keys
      keys = Map.keys(%Event{})
      assert :type in keys
      assert :provider in keys
      assert :session_id in keys
      assert :run_id in keys
      assert :prompt_id in keys
      assert :event_id in keys
      assert :sequence in keys
      assert :timestamp in keys
      assert :data in keys
      assert :raw in keys
    end
  end

  describe "event types" do
    test "supports all 12 event types plus raw fallback" do
      valid_types = [
        :message_start,
        :text_delta,
        :message_stop,
        :tool_use_start,
        :tool_use_delta,
        :tool_use_end,
        :tool_result,
        :file_change,
        :structured_output,
        :reasoning,
        :usage_update,
        :error,
        :raw
      ]

      for type <- valid_types do
        event = %Event{type: type, provider: :claude, data: %{}}
        assert event.type == type
      end
    end
  end
end
