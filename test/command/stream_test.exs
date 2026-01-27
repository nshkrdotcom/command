defmodule Command.StreamTest do
  use ExUnit.Case, async: true

  alias Command.Event
  alias Command.Stream

  describe "normalize/3" do
    test "passes through claude events with telemetry" do
      events = [
        %Event{
          type: :message_start,
          provider: :claude,
          session_id: "s1",
          run_id: "r1",
          prompt_id: "p1",
          event_id: "e1",
          sequence: 0,
          timestamp: DateTime.utc_now(),
          data: %{message_id: "m1", model: "claude-sonnet-4", role: :assistant},
          raw: %{}
        },
        %Event{
          type: :message_stop,
          provider: :claude,
          session_id: "s1",
          run_id: "r1",
          prompt_id: "p1",
          event_id: "e2",
          sequence: 1,
          timestamp: DateTime.utc_now(),
          data: %{stop_reason: :end_turn},
          raw: %{}
        }
      ]

      result = Stream.normalize(:claude, events) |> Enum.to_list()

      assert length(result) == 2
      assert Enum.all?(result, &(&1.provider == :claude))
    end

    test "passes through codex events" do
      events = [
        %Event{
          type: :message_start,
          provider: :codex,
          session_id: "t1",
          run_id: "turn_1",
          prompt_id: "p1",
          event_id: "e1",
          sequence: 0,
          timestamp: DateTime.utc_now(),
          data: %{message_id: "t1", model: nil, role: :assistant},
          raw: %{}
        }
      ]

      result = Stream.normalize(:codex, events) |> Enum.to_list()

      assert length(result) == 1
      assert Enum.all?(result, &(&1.provider == :codex))
    end

    test "raises for unknown provider" do
      assert_raise ArgumentError, ~r/Unknown provider/, fn ->
        Stream.normalize(:unknown, []) |> Enum.to_list()
      end
    end
  end
end
