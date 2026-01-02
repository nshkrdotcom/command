defmodule Command.PubSub do
  @moduledoc """
  PubSub integration for Command.

  Broadcasts events when Command resources change, allowing LiveView
  and other subscribers to receive real-time updates.

  ## Configuration

      config :command,
        pubsub: MyApp.PubSub,
        pubsub_prefix: "command"

  ## Topics

  Topics follow the pattern: `{prefix}:{resource}:{id}`

  - `command:session:{id}` - Session changes
  - `command:session:{id}:messages` - New messages in session
  - `command:session:{id}:agent_calls` - Agent call updates
  - `command:user:{id}:sessions` - Session list updates for user
  - `command:user:{id}:approvals` - Pending approvals for user
  - `command:user:{id}:costs` - Cost updates for user

  ## Usage in LiveView

      def mount(%{"id" => id}, _session, socket) do
        if connected?(socket) do
          Command.PubSub.subscribe("session:\#{id}")
          Command.PubSub.subscribe("session:\#{id}:messages")
        end
        {:ok, socket}
      end

      def handle_info({Command.PubSub, :message_created, message}, socket) do
        {:noreply, stream_insert(socket, :messages, message)}
      end
  """

  @type topic :: String.t()
  @type event :: atom()
  @type payload :: term()

  @doc """
  Returns the configured PubSub module.
  """
  @spec pubsub() :: module() | nil
  def pubsub do
    Application.get_env(:command, :pubsub)
  end

  @doc """
  Returns the topic prefix.
  """
  @spec prefix() :: String.t()
  def prefix do
    Application.get_env(:command, :pubsub_prefix, "command")
  end

  @doc """
  Broadcasts an event to a topic.

  No-op if PubSub is not configured.
  """
  @spec broadcast(topic(), event(), payload()) :: :ok | {:error, term()}
  def broadcast(topic, event, payload) do
    case pubsub() do
      nil ->
        :ok

      pubsub_mod ->
        full_topic = "#{prefix()}:#{topic}"
        Phoenix.PubSub.broadcast(pubsub_mod, full_topic, {__MODULE__, event, payload})
    end
  end

  @doc """
  Broadcasts an event from the current process.
  """
  @spec broadcast_from(topic(), event(), payload()) :: :ok | {:error, term()}
  def broadcast_from(topic, event, payload) do
    case pubsub() do
      nil ->
        :ok

      pubsub_mod ->
        full_topic = "#{prefix()}:#{topic}"

        Phoenix.PubSub.broadcast_from(
          pubsub_mod,
          self(),
          full_topic,
          {__MODULE__, event, payload}
        )
    end
  end

  @doc """
  Subscribes to a topic.
  """
  @spec subscribe(topic()) :: :ok | {:error, term()}
  def subscribe(topic) do
    case pubsub() do
      nil ->
        :ok

      pubsub_mod ->
        full_topic = "#{prefix()}:#{topic}"
        Phoenix.PubSub.subscribe(pubsub_mod, full_topic)
    end
  end

  @doc """
  Unsubscribes from a topic.
  """
  @spec unsubscribe(topic()) :: :ok
  def unsubscribe(topic) do
    case pubsub() do
      nil ->
        :ok

      pubsub_mod ->
        full_topic = "#{prefix()}:#{topic}"
        Phoenix.PubSub.unsubscribe(pubsub_mod, full_topic)
    end
  end
end
