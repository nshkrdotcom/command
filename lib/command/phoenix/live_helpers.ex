defmodule Command.Phoenix.LiveHelpers do
  @moduledoc """
  Helper functions for Command LiveView integration.
  """

  import Phoenix.LiveView
  import Phoenix.Component, only: [update: 3]

  @doc """
  Subscribes to Command PubSub topics for a session.

  Call this in mount/3 when connected.
  """
  @spec subscribe_to_session(Phoenix.LiveView.Socket.t(), Ecto.UUID.t()) ::
          Phoenix.LiveView.Socket.t()
  def subscribe_to_session(socket, session_id) do
    _ =
      if connected?(socket) do
        _ = Command.PubSub.subscribe("session:#{session_id}")
        _ = Command.PubSub.subscribe("session:#{session_id}:messages")
        _ = Command.PubSub.subscribe("session:#{session_id}:agent_calls")
      end

    socket
  end

  @doc """
  Subscribes to user-level notifications.
  """
  @spec subscribe_to_user(Phoenix.LiveView.Socket.t(), Ecto.UUID.t()) ::
          Phoenix.LiveView.Socket.t()
  def subscribe_to_user(socket, user_id) do
    _ =
      if connected?(socket) do
        _ = Command.PubSub.subscribe("user:#{user_id}:sessions")
        _ = Command.PubSub.subscribe("user:#{user_id}:approvals")
        _ = Command.PubSub.subscribe("user:#{user_id}:costs")
      end

    socket
  end

  @doc """
  Handles common Command PubSub events.

  Returns `{:handled, socket}` if handled, `{:unhandled, msg}` otherwise.
  """
  @spec handle_command_event(term(), Phoenix.LiveView.Socket.t()) ::
          {:handled, Phoenix.LiveView.Socket.t()} | {:unhandled, term()}
  def handle_command_event({Command.PubSub, :message_created, message}, socket) do
    {:handled, stream_insert(socket, :messages, message)}
  end

  def handle_command_event({Command.PubSub, :agent_call_completed, call}, socket) do
    {:handled, stream_insert(socket, :agent_calls, call)}
  end

  def handle_command_event({Command.PubSub, :approval_created, approval}, socket) do
    socket = update(socket, :pending_approval_count, &(&1 + 1))
    {:handled, stream_insert(socket, :approvals, approval)}
  end

  def handle_command_event(msg, _socket) do
    {:unhandled, msg}
  end
end
