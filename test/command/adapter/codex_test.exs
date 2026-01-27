defmodule Command.Adapter.CodexTest do
  use ExUnit.Case, async: true

  alias Command.Adapter.Codex

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

  describe "normalize_stream/2" do
    test "normalizes ThreadStarted event" do
      raw_events = [
        %CodexEvents.ThreadStarted{thread_id: "thread_123", metadata: %{model: "gpt-4.1"}}
      ]

      [event] =
        raw_events
        |> to_stream()
        |> Codex.normalize_stream(mode: :compatibility)
        |> Enum.to_list()

      assert event.type == :message_start
      assert event.provider == :codex
      assert event.session_id == "thread_123"
      assert event.data.message_id == "thread_123"
    end

    test "normalizes TurnStarted event" do
      raw_events = [
        %CodexEvents.TurnStarted{thread_id: "thread_1", turn_id: "turn_1"}
      ]

      [event] =
        raw_events
        |> to_stream()
        |> Codex.normalize_stream(mode: :compatibility)
        |> Enum.to_list()

      assert event.type == :message_start
      assert event.session_id == "thread_1"
      assert event.run_id == "turn_1"
    end

    test "normalizes AgentMessage item" do
      raw_events = [
        %CodexEvents.TurnStarted{thread_id: "t1", turn_id: "turn_1"},
        %CodexItems.AgentMessage{id: "msg_1", text: "Hello world"}
      ]

      events =
        raw_events
        |> to_stream()
        |> Codex.normalize_stream(mode: :compatibility)
        |> Enum.to_list()

      text_event = Enum.find(events, &(&1.type == :text_delta))
      assert text_event.data.content == "Hello world"
    end

    test "normalizes Reasoning item" do
      raw_events = [
        %CodexEvents.TurnStarted{thread_id: "t1", turn_id: "turn_1"},
        %CodexItems.Reasoning{id: "r1", text: "Thinking...", summary: ["Step 1", "Step 2"]}
      ]

      events =
        raw_events
        |> to_stream()
        |> Codex.normalize_stream(mode: :compatibility)
        |> Enum.to_list()

      reasoning_event = Enum.find(events, &(&1.type == :reasoning))
      assert reasoning_event.data.text == "Thinking..."
      assert reasoning_event.data.summary == "Step 1\nStep 2"
    end

    test "normalizes TurnCompleted with usage" do
      raw_events = [
        %CodexEvents.TurnStarted{thread_id: "t1", turn_id: "turn_1"},
        %CodexEvents.TurnCompleted{
          thread_id: "t1",
          turn_id: "turn_1",
          status: "completed",
          response_id: "resp_1",
          usage: %{input_tokens: 200, output_tokens: 100}
        }
      ]

      events =
        raw_events
        |> to_stream()
        |> Codex.normalize_stream(mode: :compatibility)
        |> Enum.to_list()

      usage_event = Enum.find(events, &(&1.type == :usage_update))
      assert usage_event.data.input_tokens == 200
      assert usage_event.data.output_tokens == 100

      stop_event = Enum.find(events, &(&1.type == :message_stop))
      assert stop_event.data.stop_reason == :end_turn
    end

    test "normalizes TurnFailed event" do
      raw_events = [
        %CodexEvents.TurnFailed{
          thread_id: "t1",
          turn_id: "turn_1",
          error: %{kind: :rate_limit, message: "Rate limited"}
        }
      ]

      [event] =
        raw_events
        |> to_stream()
        |> Codex.normalize_stream(mode: :compatibility)
        |> Enum.to_list()

      assert event.type == :error
      assert event.data.error_type == :rate_limit
      assert event.data.message == "Rate limited"
      assert event.data.recoverable == true
    end

    test "handles unknown event types as :raw" do
      raw_events = [
        %{type: :unknown_codex_event, data: "something"}
      ]

      [event] =
        raw_events
        |> to_stream()
        |> Codex.normalize_stream(mode: :compatibility)
        |> Enum.to_list()

      assert event.type == :raw
    end
  end

  defp to_stream(list), do: Stream.into(list, [])
end
