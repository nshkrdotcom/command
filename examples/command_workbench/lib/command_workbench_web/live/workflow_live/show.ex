defmodule CommandWorkbenchWeb.WorkflowLive.Show do
  use CommandWorkbenchWeb, :live_view

  alias Command.Workflows
  alias Command.Workflows.{WorkflowRun, WorkflowStep}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    workflow = Workflows.get_workflow(id)
    runs = Workflows.list_workflow_runs(workflow, limit: 20)

    if connected?(socket) do
      Command.PubSub.subscribe("workflow:#{workflow.id}:runs")
    end

    {:ok,
     socket
     |> assign(:page_title, workflow.name)
     |> assign(:workflow, workflow)
     |> assign(:selected_run, nil)
     |> assign(:selected_steps, [])
     |> stream(:runs, runs)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    socket
    |> assign(:selected_run, nil)
    |> assign(:selected_steps, [])
  end

  defp apply_action(socket, :run, %{"run_id" => run_id}) do
    run = Workflows.get_workflow_run(run_id)
    steps = Workflows.list_workflow_steps(run)

    if connected?(socket) do
      Command.PubSub.subscribe("workflow_run:#{run.id}:steps")
    end

    socket
    |> assign(:selected_run, run)
    |> assign(:selected_steps, steps)
  end

  @impl true
  def handle_event("start_run", _params, socket) do
    workflow = socket.assigns.workflow
    user = socket.assigns.current_user

    with {:ok, run} <- Workflows.start_workflow_run(workflow, user, %{input: %{}}),
         {:ok, run} <- Workflows.begin_workflow_run(run) do
      {:noreply, push_patch(socket, to: ~p"/workflows/#{workflow}/runs/#{run}")}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Failed to start workflow")}
    end
  end

  @impl true
  def handle_info({Command.PubSub, event, %WorkflowRun{} = run}, socket)
      when event in [:workflow_run_started, :workflow_run_completed, :workflow_run_failed] do
    socket =
      socket
      |> stream_insert(:runs, run)
      |> maybe_update_selected_run(run)

    {:noreply, socket}
  end

  def handle_info({Command.PubSub, event, %WorkflowStep{} = step}, socket)
      when event in [:workflow_step_started, :workflow_step_completed] do
    socket =
      if socket.assigns.selected_run && socket.assigns.selected_run.id == step.workflow_run_id do
        steps = Workflows.list_workflow_steps(socket.assigns.selected_run)
        assign(socket, :selected_steps, steps)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      <%= @workflow.name %>
      <:subtitle><%= @workflow.description %></:subtitle>
      <:actions>
        <.button phx-click="start_run">Start Run</.button>
      </:actions>
    </.header>

    <div class="mt-6 grid grid-cols-1 lg:grid-cols-3 gap-6">
      <div class="panel p-6 lg:col-span-2">
        <div class="grid gap-4 md:grid-cols-3">
          <div>
            <div class="text-xs uppercase tracking-wider text-slate-500">Status</div>
            <div class="text-sm font-semibold capitalize"><%= @workflow.status %></div>
          </div>
          <div>
            <div class="text-xs uppercase tracking-wider text-slate-500">Runs</div>
            <div class="text-sm font-semibold"><%= @workflow.run_count %></div>
          </div>
          <div>
            <div class="text-xs uppercase tracking-wider text-slate-500">Category</div>
            <div class="text-sm font-semibold capitalize"><%= @workflow.category %></div>
          </div>
        </div>

        <div class="mt-6">
          <h3 class="text-sm font-semibold text-slate-500 uppercase tracking-wider">
            Recent Runs
          </h3>
          <div id="runs" phx-update="stream" class="mt-3 space-y-2">
            <div
              :for={{dom_id, run} <- @streams.runs}
              id={dom_id}
              class="flex items-center justify-between rounded border border-sand-200 px-3 py-2"
            >
              <div>
                <div class="text-sm font-medium">Run <%= run.id |> String.slice(0, 8) %></div>
                <div class="text-xs text-slate-500">
                  <%= Calendar.strftime(run.inserted_at, "%b %d, %H:%M") %>
                </div>
              </div>
              <div class="flex items-center gap-2">
                <span class="text-xs uppercase tracking-wider text-slate-500"><%= run.status %></span>
                <.link navigate={~p"/workflows/#{@workflow}/runs/#{run}"}>
                  <.button size="sm" variant="secondary">View</.button>
                </.link>
              </div>
            </div>

            <div :if={Enum.empty?(@streams.runs)} class="text-sm text-slate-500">
              No runs yet.
            </div>
          </div>
        </div>
      </div>

      <div class="panel p-6">
        <%= if @selected_run do %>
          <.live_component
            module={CommandWorkbenchWeb.WorkflowLive.RunComponent}
            id={@selected_run.id}
            run={@selected_run}
            steps={@selected_steps}
          />
        <% else %>
          <div class="text-sm text-slate-500">
            Select a run to see details.
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp maybe_update_selected_run(socket, run) do
    if socket.assigns.selected_run && socket.assigns.selected_run.id == run.id do
      assign(socket, :selected_run, run)
    else
      socket
    end
  end
end
