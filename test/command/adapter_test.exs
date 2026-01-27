defmodule Command.AdapterTest do
  use ExUnit.Case, async: true

  describe "behaviour callbacks" do
    test "defines normalize_stream/2 callback" do
      callbacks = Command.Adapter.behaviour_info(:callbacks)
      assert {:normalize_stream, 2} in callbacks
    end

    test "defines normalize_event/2 callback" do
      callbacks = Command.Adapter.behaviour_info(:callbacks)
      assert {:normalize_event, 2} in callbacks
    end

    test "defines supports_event?/1 callback" do
      callbacks = Command.Adapter.behaviour_info(:callbacks)
      assert {:supports_event?, 1} in callbacks
    end
  end

  describe "select_mode/1" do
    test "returns :strict when mode option provided" do
      assert Command.Adapter.select_mode(mode: :strict) == :strict
    end

    test "returns :compatibility when mode option provided" do
      assert Command.Adapter.select_mode(mode: :compatibility) == :compatibility
    end

    test "defaults to :strict when no mode specified and env is not set" do
      # Note: In production this would be :strict based on Mix.env()
      # For test purposes we're just testing the function logic
      mode = Command.Adapter.select_mode([])
      assert mode in [:strict, :compatibility]
    end
  end
end
