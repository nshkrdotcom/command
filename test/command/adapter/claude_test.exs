defmodule Command.Adapter.ClaudeTest do
  use ExUnit.Case, async: true

  alias Command.Adapter.Claude
  alias Command.Event

  describe "normalize_stream/2" do
    test "normalizes message_start event" do
      raw_events = [
        %{
          "type" => "message_start",
          "message" => %{"id" => "msg_123", "model" => "claude-sonnet-4"},
          "session_id" => "session_abc"
        }
      ]

      [event] =
        raw_events
        |> to_stream()
        |> Claude.normalize_stream(mode: :compatibility)
        |> Enum.to_list()

      assert event.type == :message_start
      assert event.provider == :claude
      assert event.session_id == "session_abc"
      assert event.data.message_id == "msg_123"
      assert event.data.model == "claude-sonnet-4"
      assert event.data.role == :assistant
    end

    test "normalizes text content_block_delta" do
      raw_events = [
        %{
          "type" => "message_start",
          "message" => %{"id" => "msg_1"},
          "session_id" => "s1"
        },
        %{
          "type" => "content_block_delta",
          "delta" => %{"type" => "text_delta", "text" => "Hello"},
          "index" => 0
        }
      ]

      events =
        raw_events
        |> to_stream()
        |> Claude.normalize_stream(mode: :compatibility)
        |> Enum.to_list()

      text_event = Enum.find(events, &(&1.type == :text_delta))
      assert text_event.data.content == "Hello"
      assert text_event.data.content_block_index == 0
    end

    test "normalizes tool_use content_block_start" do
      raw_events = [
        %{
          "type" => "message_start",
          "message" => %{"id" => "msg_1"},
          "session_id" => "s1"
        },
        %{
          "type" => "content_block_start",
          "content_block" => %{"type" => "tool_use", "id" => "tool_1", "name" => "Read"},
          "index" => 0
        }
      ]

      events =
        raw_events
        |> to_stream()
        |> Claude.normalize_stream(mode: :compatibility)
        |> Enum.to_list()

      tool_event = Enum.find(events, &(&1.type == :tool_use_start))
      assert tool_event.data.tool_use_id == "tool_1"
      assert tool_event.data.tool_name == "Read"
    end

    test "accumulates tool input JSON fragments" do
      raw_events = [
        %{
          "type" => "message_start",
          "message" => %{"id" => "msg_1"},
          "session_id" => "s1"
        },
        %{
          "type" => "content_block_start",
          "content_block" => %{"type" => "tool_use", "id" => "tool_1", "name" => "Read"},
          "index" => 0
        },
        %{
          "type" => "content_block_delta",
          "delta" => %{"type" => "input_json_delta", "partial_json" => "{\"file\""},
          "index" => 0
        },
        %{
          "type" => "content_block_delta",
          "delta" => %{"type" => "input_json_delta", "partial_json" => ": \"test.txt\"}"},
          "index" => 0
        },
        %{
          "type" => "content_block_stop",
          "index" => 0
        }
      ]

      events =
        raw_events
        |> to_stream()
        |> Claude.normalize_stream(mode: :compatibility)
        |> Enum.to_list()

      end_event = Enum.find(events, &(&1.type == :tool_use_end))
      assert end_event.data.input == %{"file" => "test.txt"}
    end

    test "normalizes message_stop event" do
      raw_events = [
        %{
          "type" => "message_start",
          "message" => %{"id" => "msg_1"},
          "session_id" => "s1"
        },
        %{
          "type" => "message_stop",
          "stop_reason" => "end_turn"
        }
      ]

      events =
        raw_events
        |> to_stream()
        |> Claude.normalize_stream(mode: :compatibility)
        |> Enum.to_list()

      stop_event = Enum.find(events, &(&1.type == :message_stop))
      assert stop_event.data.stop_reason == :end_turn
    end

    test "normalizes error event" do
      raw_events = [
        %{
          "type" => "error",
          "error" => %{"type" => "overloaded_error", "message" => "Server overloaded"}
        }
      ]

      [event] =
        raw_events
        |> to_stream()
        |> Claude.normalize_stream(mode: :compatibility)
        |> Enum.to_list()

      assert event.type == :error
      assert event.data.error_type == :rate_limit
      assert event.data.message == "Server overloaded"
      assert event.data.recoverable == true
    end

    test "normalizes usage in message_delta" do
      raw_events = [
        %{
          "type" => "message_start",
          "message" => %{"id" => "msg_1"},
          "session_id" => "s1"
        },
        %{
          "type" => "message_delta",
          "usage" => %{"input_tokens" => 100, "output_tokens" => 50}
        }
      ]

      events =
        raw_events
        |> to_stream()
        |> Claude.normalize_stream(mode: :compatibility)
        |> Enum.to_list()

      usage_event = Enum.find(events, &(&1.type == :usage_update))
      assert usage_event.data.input_tokens == 100
      assert usage_event.data.output_tokens == 50
    end

    test "handles unknown event types as :raw" do
      raw_events = [
        %{"type" => "unknown_event_type", "data" => "something"}
      ]

      [event] =
        raw_events
        |> to_stream()
        |> Claude.normalize_stream(mode: :compatibility)
        |> Enum.to_list()

      assert event.type == :raw
      assert event.data.original_type == "unknown_event_type"
    end

    test "maintains sequence order" do
      raw_events = [
        %{"type" => "message_start", "message" => %{"id" => "m1"}, "session_id" => "s1"},
        %{
          "type" => "content_block_delta",
          "delta" => %{"type" => "text_delta", "text" => "A"},
          "index" => 0
        },
        %{
          "type" => "content_block_delta",
          "delta" => %{"type" => "text_delta", "text" => "B"},
          "index" => 0
        },
        %{"type" => "message_stop", "stop_reason" => "end_turn"}
      ]

      events =
        raw_events
        |> to_stream()
        |> Claude.normalize_stream(mode: :compatibility)
        |> Enum.to_list()

      sequences = Enum.map(events, & &1.sequence)
      assert sequences == Enum.sort(sequences)
      assert Enum.uniq(sequences) == sequences
    end
  end

  describe "strict mode" do
    test "uses fallback for missing session_id in compatibility mode" do
      raw_events = [
        %{"type" => "message_start", "message" => %{"id" => "msg_1"}}
        # No session_id
      ]

      [event] =
        raw_events
        |> to_stream()
        |> Claude.normalize_stream(mode: :compatibility)
        |> Enum.to_list()

      # Should generate a fallback session_id
      assert is_binary(event.session_id)
    end
  end

  defp to_stream(list), do: Stream.into(list, [])
end
