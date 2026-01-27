defmodule Command.Adapter.ValidationTest do
  use ExUnit.Case, async: true

  alias Command.Adapter.Validation
  alias Command.Event

  describe "validate!/1" do
    test "returns event when all required fields present" do
      event = build_valid_event(:text_delta, %{content: "hi", content_block_index: 0})
      assert %Event{} = Validation.validate!(event)
    end

    test "raises for missing type" do
      event = %Event{
        type: nil,
        provider: :claude,
        event_id: "e1",
        sequence: 0,
        timestamp: DateTime.utc_now(),
        data: %{}
      }

      assert_raise ArgumentError, ~r/Invalid event/, fn ->
        Validation.validate!(event)
      end
    end

    test "raises for missing provider" do
      event = %Event{
        type: :text_delta,
        provider: nil,
        event_id: "e1",
        sequence: 0,
        timestamp: DateTime.utc_now(),
        data: %{}
      }

      assert_raise ArgumentError, ~r/Invalid event/, fn ->
        Validation.validate!(event)
      end
    end

    test "raises for missing session_id in strict mode" do
      event = %Event{
        type: :text_delta,
        provider: :claude,
        session_id: nil,
        run_id: "r1",
        event_id: "e1",
        sequence: 0,
        timestamp: DateTime.utc_now(),
        data: %{content: "hi", content_block_index: 0}
      }

      assert_raise ArgumentError, ~r/Invalid event/, fn ->
        Validation.validate!(event)
      end
    end

    test "validates data shape for text_delta" do
      # Missing content field
      event = build_valid_event(:text_delta, %{})

      assert_raise ArgumentError, ~r/Invalid event/, fn ->
        Validation.validate!(event)
      end
    end

    test "validates data shape for tool_use_start" do
      # Missing tool_use_id
      event = build_valid_event(:tool_use_start, %{tool_name: "test"})

      assert_raise ArgumentError, ~r/Invalid event/, fn ->
        Validation.validate!(event)
      end
    end

    test "validates data shape for error" do
      event =
        build_valid_event(:error, %{
          error_type: :rate_limit,
          message: "Too many requests",
          recoverable: true
        })

      assert %Event{} = Validation.validate!(event)
    end

    test "accepts nil values for optional data fields" do
      event =
        build_valid_event(:error, %{
          error_type: :rate_limit,
          message: "Too many requests",
          recoverable: true,
          code: nil,
          retry_after_ms: nil
        })

      assert %Event{} = Validation.validate!(event)
    end
  end

  describe "validate/1" do
    test "returns {:ok, event} for valid event" do
      event = build_valid_event(:text_delta, %{content: "hi", content_block_index: 0})
      assert {:ok, %Event{}} = Validation.validate(event)
    end

    test "returns {:error, reason} for invalid event" do
      event = %Event{type: nil, provider: :claude}
      assert {:error, _reason} = Validation.validate(event)
    end
  end

  defp build_valid_event(type, data) do
    %Event{
      type: type,
      provider: :claude,
      session_id: "session-1",
      run_id: "run-1",
      prompt_id: "prompt-1",
      event_id: "event-1",
      sequence: 0,
      timestamp: DateTime.utc_now(),
      data: data,
      raw: %{}
    }
  end
end
