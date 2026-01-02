defmodule CommandWorkbenchWeb.WorkflowLive.Index do
  use CommandWorkbenchWeb, :live_view

  alias Command.Workflows
  alias Command.Workflows.Workflow

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if connected?(socket) do
      Command.PubSub.subscribe("user:#{user.id}:workflows")
    end

    workflows = Workflows.list_workflows(user, limit: 50)

    {:ok,
     socket
     |> assign(:page_title, "Workflows")
     |> stream(:workflows, workflows)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:workflow, nil)
    |> assign(:form, nil)
  end

  defp apply_action(socket, :new, _params) do
    workflow = %Workflow{}
    form = workflow |> Workflows.change_workflow() |> to_form()

    socket
    |> assign(:page_title, "New Workflow")
    |> assign(:workflow, workflow)
    |> assign(:form, form)
  end

  @impl true
  def handle_event("validate", %{"workflow" => params}, socket) do
    user = socket.assigns.current_user

    params =
      params
      |> Map.put_new("user_id", user.id)
      |> normalize_tags()
      |> ensure_slug()

    changeset =
      socket.assigns.workflow
      |> Workflows.change_workflow(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"workflow" => params}, socket) do
    user = socket.assigns.current_user

    params =
      params
      |> normalize_tags()
      |> ensure_slug()

    case Workflows.create_workflow(user, params) do
      {:ok, workflow} ->
        {:noreply,
         socket
         |> put_flash(:info, "Workflow created")
         |> push_patch(to: ~p"/workflows")
         |> stream_insert(:workflows, workflow, at: 0)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_info({Command.PubSub, :workflow_created, workflow}, socket) do
    {:noreply, stream_insert(socket, :workflows, workflow, at: 0)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Workflows
      <:actions>
        <.link patch={~p"/workflows/new"}>
          <.button>New Workflow</.button>
        </.link>
      </:actions>
    </.header>

    <.table
      id="workflows"
      rows={@streams.workflows}
      row_click={fn {_id, workflow} -> JS.navigate(~p"/workflows/#{workflow}") end}
    >
      <:col :let={{_id, workflow}} label="Name"><%= workflow.name %></:col>
      <:col :let={{_id, workflow}} label="Status"><%= workflow.status %></:col>
      <:col :let={{_id, workflow}} label="Runs"><%= workflow.run_count %></:col>
      <:col :let={{_id, workflow}} label="Updated">
        <%= Calendar.strftime(workflow.updated_at, "%b %d, %H:%M") %>
      </:col>
      <:action :let={{_id, workflow}}>
        <.link navigate={~p"/workflows/#{workflow}"}>Show</.link>
      </:action>
    </.table>

    <.modal
      :if={@live_action == :new}
      id="workflow-modal"
      show
      on_cancel={JS.patch(~p"/workflows")}
    >
      <div>
        <.header>
          New Workflow
        </.header>

        <.simple_form for={@form} phx-change="validate" phx-submit="save">
          <.input field={@form[:name]} type="text" label="Name" />
          <.input field={@form[:description]} type="textarea" label="Description" rows={3} />
          <.input
            field={@form[:category]}
            type="select"
            label="Category"
            options={[
              {"Code Review", "code_review"},
              {"Refactor", "refactor"},
              {"Documentation", "documentation"},
              {"Testing", "testing"},
              {"Deployment", "deployment"},
              {"Custom", "custom"}
            ]}
          />
          <.input
            field={@form[:tags]}
            type="text"
            label="Tags"
            placeholder="comma-separated"
          />
          <:actions>
            <.button phx-disable-with="Saving...">Create Workflow</.button>
          </:actions>
        </.simple_form>
      </div>
    </.modal>
    """
  end

  defp ensure_slug(params) do
    slug = Map.get(params, "slug") || ""

    if slug == "" do
      name = Map.get(params, "name", "")
      Map.put(params, "slug", slugify(name))
    else
      params
    end
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.slice(0, 50)
  end

  defp normalize_tags(params) do
    case Map.get(params, "tags") do
      nil ->
        params

      "" ->
        Map.put(params, "tags", [])

      tags when is_binary(tags) ->
        parsed =
          tags
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        Map.put(params, "tags", parsed)

      _ ->
        params
    end
  end
end
