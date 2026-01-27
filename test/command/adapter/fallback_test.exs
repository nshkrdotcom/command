defmodule Command.Adapter.FallbackTest do
  use ExUnit.Case, async: true

  alias Command.Adapter.Fallback
  alias Command.Event

  describe "apply_fallbacks/2" do
    test "fills nil session_id from state" do
      event = %Event{type: :text_delta, provider: :claude, session_id: nil}
      state = %{session_id: "state-session", run_id: "r1", sequence: 0}

      result = Fallback.apply_fallbacks(event, state)

      assert result.session_id == "state-session"
    end

    test "fills nil session_id with UUID when state has no session_id" do
      event = %Event{type: :text_delta, provider: :claude, session_id: nil}
      state = %{session_id: nil, run_id: nil, sequence: 0}

      result = Fallback.apply_fallbacks(event, state)

      assert is_binary(result.session_id)
      assert String.length(result.session_id) > 0
    end

    test "preserves existing session_id" do
      event = %Event{type: :text_delta, provider: :claude, session_id: "existing"}
      state = %{session_id: "state-session", run_id: nil, sequence: 0}

      result = Fallback.apply_fallbacks(event, state)

      assert result.session_id == "existing"
    end

    test "fills nil run_id from state" do
      event = %Event{type: :text_delta, provider: :claude, run_id: nil}
      state = %{session_id: nil, run_id: "state-run", sequence: 0}

      result = Fallback.apply_fallbacks(event, state)

      assert result.run_id == "state-run"
    end

    test "fills nil run_id with UUID when state has no run_id" do
      event = %Event{type: :text_delta, provider: :claude, run_id: nil}
      state = %{session_id: nil, run_id: nil, sequence: 0}

      result = Fallback.apply_fallbacks(event, state)

      assert is_binary(result.run_id)
    end

    test "fills nil event_id with generated UUID" do
      event = %Event{type: :text_delta, provider: :claude, event_id: nil}
      state = %{session_id: nil, run_id: nil, sequence: 0}

      result = Fallback.apply_fallbacks(event, state)

      assert is_binary(result.event_id)
    end

    test "fills nil timestamp with current time" do
      event = %Event{type: :text_delta, provider: :claude, timestamp: nil}
      state = %{session_id: nil, run_id: nil, sequence: 0}

      before = DateTime.utc_now()
      result = Fallback.apply_fallbacks(event, state)
      after_time = DateTime.utc_now()

      assert %DateTime{} = result.timestamp
      assert DateTime.compare(result.timestamp, before) in [:gt, :eq]
      assert DateTime.compare(result.timestamp, after_time) in [:lt, :eq]
    end

    test "fills nil sequence from state" do
      event = %Event{type: :text_delta, provider: :claude, sequence: nil}
      state = %{session_id: nil, run_id: nil, sequence: 42}

      result = Fallback.apply_fallbacks(event, state)

      assert result.sequence == 42
    end

    test "fills nil data with empty map" do
      event = %Event{type: :text_delta, provider: :claude, data: nil}
      state = %{session_id: nil, run_id: nil, sequence: 0}

      result = Fallback.apply_fallbacks(event, state)

      assert result.data == %{}
    end

    test "fills all nil fields at once" do
      event = %Event{
        type: :text_delta,
        provider: :claude,
        session_id: nil,
        run_id: nil,
        event_id: nil,
        timestamp: nil,
        sequence: nil,
        data: nil
      }

      state = %{session_id: nil, run_id: nil, sequence: 0}

      result = Fallback.apply_fallbacks(event, state)

      assert is_binary(result.session_id)
      assert is_binary(result.run_id)
      assert is_binary(result.event_id)
      assert %DateTime{} = result.timestamp
      assert result.sequence == 0
      assert result.data == %{}
    end

    test "preserves all existing non-nil fields" do
      now = DateTime.utc_now()

      event = %Event{
        type: :text_delta,
        provider: :claude,
        session_id: "s1",
        run_id: "r1",
        prompt_id: "p1",
        event_id: "e1",
        sequence: 5,
        timestamp: now,
        data: %{content: "hello"},
        raw: %{}
      }

      state = %{session_id: "other", run_id: "other", sequence: 99}

      result = Fallback.apply_fallbacks(event, state)

      assert result.session_id == "s1"
      assert result.run_id == "r1"
      assert result.prompt_id == "p1"
      assert result.event_id == "e1"
      assert result.sequence == 5
      assert result.timestamp == now
      assert result.data == %{content: "hello"}
    end
  end

  describe "generate_fallback/1" do
    test "returns a UUID string" do
      result = Fallback.generate_fallback(:test_field)

      assert is_binary(result)
      # UUID format: 8-4-4-4-12
      assert Regex.match?(
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[089ab][0-9a-f]{3}-[0-9a-f]{12}$/,
               result
             )
    end

    test "generates unique values on each call" do
      a = Fallback.generate_fallback(:field_a)
      b = Fallback.generate_fallback(:field_b)

      assert a != b
    end
  end
end
