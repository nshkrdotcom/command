defmodule Command.StreamTest do
  use ExUnit.Case, async: true

  alias Command.Stream

  describe "normalize/3" do
    test "routes claude streams to Claude adapter" do
      raw_events = [
        %{"type" => "message_start", "message" => %{"id" => "m1"}, "session_id" => "s1"},
        %{"type" => "message_stop", "stop_reason" => "end_turn"}
      ]

      events = Stream.normalize(:claude, raw_events, mode: :compatibility) |> Enum.to_list()

      assert Enum.all?(events, &(&1.provider == :claude))
    end

    test "routes codex streams to Codex adapter" do
      # Use map-based events that Codex adapter will treat as raw
      raw_events = [
        %{type: :thread_started, thread_id: "t1"}
      ]

      events = Stream.normalize(:codex, raw_events, mode: :compatibility) |> Enum.to_list()

      assert Enum.all?(events, &(&1.provider == :codex))
    end

    test "raises for unknown provider" do
      assert_raise ArgumentError, ~r/Unknown provider/, fn ->
        Stream.normalize(:unknown, [], mode: :compatibility) |> Enum.to_list()
      end
    end
  end
end
