defmodule CommandWorkbenchWeb.ApprovalLive.Show do
  use CommandWorkbenchWeb, :live_view

  alias Command.Approvals

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    item = Approvals.get_approval_item(id)
    user = socket.assigns.current_user

    if connected?(socket) do
      Command.PubSub.subscribe("user:#{user.id}:approvals")
    end

    {:ok,
     socket
     |> assign(:page_title, "Approval Details")
     |> assign(:item, item)}
  end

  @impl true
  def handle_event("approve", _params, socket) do
    item = socket.assigns.item
    user = socket.assigns.current_user

    case Approvals.approve_item(item, user) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:item, updated)
         |> put_flash(:info, "Approval approved")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to approve")}
    end
  end

  def handle_event("deny", _params, socket) do
    item = socket.assigns.item
    user = socket.assigns.current_user

    case Approvals.deny_item(item, user, %{decision_note: "Denied by user"}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:item, updated)
         |> put_flash(:info, "Approval denied")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to deny")}
    end
  end

  @impl true
  def handle_info({Command.PubSub, event, item}, socket)
      when event in [:approval_approved, :approval_denied, :approval_expired] do
    if socket.assigns.item.id == item.id do
      {:noreply, assign(socket, :item, item)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Approval Details
      <:subtitle><%= @item.title %></:subtitle>
      <:actions>
        <.link navigate={~p"/approvals"}>
          <.button variant="secondary">Back</.button>
        </.link>
      </:actions>
    </.header>

    <div class="mt-6 grid gap-6 lg:grid-cols-3">
      <div class="panel p-6 lg:col-span-2">
        <div class="flex items-start justify-between">
          <div>
            <h2 class="text-lg font-semibold"><%= @item.title %></h2>
            <p :if={@item.description} class="mt-2 text-slate-600">
              <%= @item.description %>
            </p>
          </div>
          <.approval_status status={@item.status} />
        </div>

        <div class="mt-6">
          <h3 class="text-sm font-semibold text-slate-500 uppercase tracking-wider">
            Payload
          </h3>
          <pre class="mt-2 text-xs bg-slate-50 p-4 rounded overflow-x-auto">
            <%= Jason.encode!(@item.payload, pretty: true) %>
          </pre>
        </div>
      </div>

      <div class="panel p-6 space-y-4">
        <div>
          <div class="text-xs uppercase tracking-wider text-slate-500">Priority</div>
          <div class="text-sm font-semibold capitalize"><%= @item.priority %></div>
        </div>
        <div>
          <div class="text-xs uppercase tracking-wider text-slate-500">Type</div>
          <div class="text-sm font-semibold capitalize"><%= @item.approval_type %></div>
        </div>
        <div>
          <div class="text-xs uppercase tracking-wider text-slate-500">Expires</div>
          <div class="text-sm font-semibold">
            <%= if @item.expires_at, do: Calendar.strftime(@item.expires_at, "%b %d, %H:%M"), else: "No expiry" %>
          </div>
        </div>

        <div class="pt-4 flex gap-2">
          <.button phx-click="approve" disabled={@item.status != "pending"}>Approve</.button>
          <.button
            variant="secondary"
            phx-click="deny"
            disabled={@item.status != "pending"}
          >
            Deny
          </.button>
        </div>
      </div>
    </div>
    """
  end
end
