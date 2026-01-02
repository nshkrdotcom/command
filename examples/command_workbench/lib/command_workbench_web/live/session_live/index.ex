defmodule CommandWorkbenchWeb.SessionLive.Index do
  use CommandWorkbenchWeb, :live_view

  alias Command.Sessions
  alias Command.Sessions.Session

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if connected?(socket) do
      Command.PubSub.subscribe("user:#{user.id}:sessions")
    end

    sessions = Sessions.list_sessions(user, limit: 50)

    {:ok,
     socket
     |> assign(:page_title, "Sessions")
     |> stream(:sessions, sessions)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:session, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Session")
    |> assign(:session, %Session{})
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    session = Sessions.get_session!(id)
    {:ok, _} = Sessions.archive_session(session)
    {:noreply, stream_delete(socket, :sessions, session)}
  end

  @impl true
  def handle_info({Command.PubSub, :session_created, session}, socket) do
    {:noreply, stream_insert(socket, :sessions, session, at: 0)}
  end

  def handle_info({Command.PubSub, :session_updated, session}, socket) do
    {:noreply, stream_insert(socket, :sessions, session)}
  end

  def handle_info({Command.PubSub, :session_archived, session}, socket) do
    {:noreply, stream_delete(socket, :sessions, session)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Sessions
      <:actions>
        <.link patch={~p"/sessions/new"}>
          <.button>New Session</.button>
        </.link>
      </:actions>
    </.header>

    <.table
      id="sessions"
      rows={@streams.sessions}
      row_click={fn {_id, session} -> JS.navigate(~p"/sessions/#{session}") end}
    >
      <:col :let={{_id, session}} label="Name"><%= session.name %></:col>
      <:col :let={{_id, session}} label="Status">
        <.session_status status={session.status} />
      </:col>
      <:col :let={{_id, session}} label="Messages"><%= session.message_count %></:col>
      <:col :let={{_id, session}} label="Cost">
        <.cost_display cents={session.total_cost_cents} />
      </:col>
      <:col :let={{_id, session}} label="Updated">
        <%= Calendar.strftime(session.updated_at, "%b %d, %H:%M") %>
      </:col>
      <:action :let={{_id, session}}>
        <.link navigate={~p"/sessions/#{session}"}>Show</.link>
      </:action>
      <:action :let={{id, session}}>
        <.link
          phx-click={JS.push("delete", value: %{id: session.id}) |> JS.hide("##{id}")}
          data-confirm="Archive this session?"
        >
          Archive
        </.link>
      </:action>
    </.table>

    <.modal
      :if={@live_action == :new}
      id="session-modal"
      show
      on_cancel={JS.patch(~p"/sessions")}
    >
      <.live_component
        module={CommandWorkbenchWeb.SessionLive.FormComponent}
        id={:new}
        title="New Session"
        action={@live_action}
        session={@session}
        current_user={@current_user}
        patch={~p"/sessions"}
      />
    </.modal>
    """
  end
end
