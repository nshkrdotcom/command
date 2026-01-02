defmodule CommandWorkbenchWeb.ApprovalLive.Index do
  use CommandWorkbenchWeb, :live_view

  alias Command.Approvals

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if connected?(socket) do
      Command.PubSub.subscribe("user:#{user.id}:approvals")
    end

    approvals = Approvals.list_pending_approvals(user, limit: 50)

    {:ok,
     socket
     |> assign(:page_title, "Approvals")
     |> stream(:approvals, approvals)}
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    item = Approvals.get_approval_item(id)
    user = socket.assigns.current_user

    case Approvals.approve_item(item, user) do
      {:ok, _} ->
        {:noreply, stream_delete(socket, :approvals, item)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to approve")}
    end
  end

  def handle_event("deny", %{"id" => id}, socket) do
    item = Approvals.get_approval_item(id)
    user = socket.assigns.current_user

    case Approvals.deny_item(item, user, %{decision_note: "Denied by user"}) do
      {:ok, _} ->
        {:noreply, stream_delete(socket, :approvals, item)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to deny")}
    end
  end

  @impl true
  def handle_info({Command.PubSub, :approval_created, item}, socket) do
    {:noreply, stream_insert(socket, :approvals, item, at: 0)}
  end

  def handle_info({Command.PubSub, event, item}, socket)
      when event in [:approval_approved, :approval_denied, :approval_expired] do
    {:noreply, stream_delete(socket, :approvals, item)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Pending Approvals
    </.header>

    <div id="approvals" phx-update="stream" class="mt-6 space-y-4">
      <div
        :for={{dom_id, item} <- @streams.approvals}
        id={dom_id}
        class="panel p-4"
      >
        <div class="flex items-start justify-between">
          <div>
            <h3 class="font-medium"><%= item.title %></h3>
            <p :if={item.description} class="text-sm text-slate-600 mt-1">
              <%= item.description %>
            </p>
          </div>
          <.approval_status status={item.status} />
        </div>

        <div class="mt-3 bg-slate-50 rounded p-3">
          <pre class="text-xs overflow-x-auto">
            <%= Jason.encode!(item.payload, pretty: true) %>
          </pre>
        </div>

        <div class="mt-4 flex gap-2">
          <.button phx-click="approve" phx-value-id={item.id}>
            Approve
          </.button>
          <.button variant="secondary" phx-click="deny" phx-value-id={item.id}>
            Deny
          </.button>
          <.link navigate={~p"/approvals/#{item}"} class="ml-auto">
            <.button variant="ghost">Details</.button>
          </.link>
        </div>
      </div>

      <div :if={Enum.empty?(@streams.approvals)} class="text-center py-12 text-slate-500">
        No pending approvals
      </div>
    </div>
    """
  end
end
