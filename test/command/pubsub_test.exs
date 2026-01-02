defmodule Command.PubSubTest do
  use ExUnit.Case, async: false

  setup do
    Application.put_env(:command, :pubsub, Command.TestPubSub)
    Application.put_env(:command, :pubsub_prefix, "test")

    start_supervised!({Phoenix.PubSub, name: Command.TestPubSub})

    on_exit(fn ->
      Application.delete_env(:command, :pubsub)
      Application.delete_env(:command, :pubsub_prefix)
    end)

    :ok
  end

  test "broadcast/3 sends message to subscribers" do
    Command.PubSub.subscribe("session:123")
    Command.PubSub.broadcast("session:123", :test_event, %{data: "test"})

    assert_receive {Command.PubSub, :test_event, %{data: "test"}}
  end

  test "broadcast_from/3 excludes sender" do
    Command.PubSub.subscribe("session:123")
    Command.PubSub.broadcast_from("session:123", :test_event, %{data: "test"})

    refute_receive {Command.PubSub, :test_event, _}
  end

  test "broadcast/3 is no-op when pubsub not configured" do
    Application.delete_env(:command, :pubsub)
    assert :ok = Command.PubSub.broadcast("topic", :event, %{})
  end
end
