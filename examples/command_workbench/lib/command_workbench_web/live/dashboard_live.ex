defmodule CommandWorkbenchWeb.DashboardLive do
  use CommandWorkbenchWeb, :live_view

  alias Command.{Approvals, Costs, Sessions, Workflows}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if connected?(socket) do
      Command.PubSub.subscribe("user:#{user.id}:sessions")
      Command.PubSub.subscribe("user:#{user.id}:approvals")
      Command.PubSub.subscribe("user:#{user.id}:costs")
      Command.PubSub.subscribe("user:#{user.id}:workflows")
    end

    {:ok, load_dashboard(socket, user)}
  end

  @impl true
  def handle_info({Command.PubSub, _event, _payload}, socket) do
    {:noreply, load_dashboard(socket, socket.assigns.current_user)}
  end

  defp load_dashboard(socket, user) do
    socket
    |> assign(:page_title, "Dashboard")
    |> assign(:recent_sessions, Sessions.list_sessions(user, limit: 5))
    |> assign(:pending_approvals, Approvals.list_pending_approvals(user, limit: 5))
    |> assign(:recent_workflows, Workflows.list_workflows(user, limit: 5))
    |> assign(:daily_cost, Costs.get_daily_cost(user))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Command Workbench
      <:subtitle>Live integration snapshot</:subtitle>
      <:actions>
        <.link navigate={~p"/sessions/new"}>
          <.button>Start Session</.button>
        </.link>
      </:actions>
    </.header>

    <div class="mt-6 grid gap-6 lg:grid-cols-3">
      <div class="panel p-6">
        <div class="text-xs uppercase tracking-wider text-slate-500">Daily Cost</div>
        <div class="mt-2 text-3xl font-semibold"><.cost_display cents={@daily_cost} /></div>
        <p class="mt-2 text-sm text-slate-600">
          Rolling view of today’s spend across providers.
        </p>
      </div>
      <div class="panel p-6">
        <div class="text-xs uppercase tracking-wider text-slate-500">Pending Approvals</div>
        <div class="mt-2 text-3xl font-semibold"><%= length(@pending_approvals) %></div>
        <p class="mt-2 text-sm text-slate-600">
          Human-in-the-loop actions waiting on your input.
        </p>
        <.link navigate={~p"/approvals"} class="mt-4 inline-flex">
          <.button size="sm" variant="secondary">Review Queue</.button>
        </.link>
      </div>
      <div class="panel p-6">
        <div class="text-xs uppercase tracking-wider text-slate-500">Active Sessions</div>
        <div class="mt-2 text-3xl font-semibold"><%= length(@recent_sessions) %></div>
        <p class="mt-2 text-sm text-slate-600">
          Recent conversations and agent activity.
        </p>
        <.link navigate={~p"/sessions"} class="mt-4 inline-flex">
          <.button size="sm" variant="secondary">Browse Sessions</.button>
        </.link>
      </div>
    </div>

    <div class="mt-8 grid gap-6 lg:grid-cols-2">
      <div class="panel p-6">
        <h3 class="font-medium mb-4">Recent Sessions</h3>
        <div class="space-y-3">
          <div :for={session <- @recent_sessions} class="flex items-center justify-between">
            <div>
              <div class="text-sm font-medium"><%= session.name %></div>
              <div class="text-xs text-slate-500"><%= session.status %></div>
            </div>
            <.link navigate={~p"/sessions/#{session}"}>
              <.button size="sm" variant="ghost">Open</.button>
            </.link>
          </div>
          <div :if={@recent_sessions == []} class="text-sm text-slate-500">
            No sessions yet.
          </div>
        </div>
      </div>

      <div class="panel p-6">
        <h3 class="font-medium mb-4">Recent Workflows</h3>
        <div class="space-y-3">
          <div :for={workflow <- @recent_workflows} class="flex items-center justify-between">
            <div>
              <div class="text-sm font-medium"><%= workflow.name %></div>
              <div class="text-xs text-slate-500"><%= workflow.status %></div>
            </div>
            <.link navigate={~p"/workflows/#{workflow}"}>
              <.button size="sm" variant="ghost">Open</.button>
            </.link>
          </div>
          <div :if={@recent_workflows == []} class="text-sm text-slate-500">
            No workflows yet.
          </div>
        </div>
      </div>
    </div>
    """
  end
end
