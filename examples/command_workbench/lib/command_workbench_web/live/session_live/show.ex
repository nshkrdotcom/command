defmodule CommandWorkbenchWeb.SessionLive.Show do
  use CommandWorkbenchWeb, :live_view

  alias Command.Agents
  alias Command.Sessions

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    session = Sessions.get_session!(id)
    messages = Sessions.list_messages(session)
    pending_tools = Agents.list_pending_tool_uses(session)

    if connected?(socket) do
      Command.PubSub.subscribe("session:#{id}")
      Command.PubSub.subscribe("session:#{id}:messages")
      Command.PubSub.subscribe("session:#{id}:agent_calls")
    end

    {:ok,
     socket
     |> assign(:page_title, session.name)
     |> assign(:session, session)
     |> assign(:pending_tools, pending_tools)
     |> assign(:message_form, to_form(%{"content" => ""}))
     |> stream(:messages, messages)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params), do: socket

  defp apply_action(socket, :edit, _params) do
    socket
    |> assign(:page_title, "Edit Session")
  end

  @impl true
  def handle_event("send_message", %{"content" => content}, socket) do
    session = socket.assigns.session

    case Sessions.create_message(session, %{role: "user", content: content}) do
      {:ok, _message} ->
        {:noreply, assign(socket, :message_form, to_form(%{"content" => ""}))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to send message")}
    end
  end

  def handle_event("approve_tool", %{"id" => tool_id}, socket) do
    tool_use = Agents.get_tool_use(tool_id)
    user = socket.assigns.current_user

    case Agents.approve_tool_use(tool_use, %{approved_by_id: user.id}) do
      {:ok, _} ->
        pending = Enum.reject(socket.assigns.pending_tools, &(&1.id == tool_id))
        {:noreply, assign(socket, :pending_tools, pending)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to approve")}
    end
  end

  def handle_event("deny_tool", %{"id" => tool_id, "reason" => reason}, socket) do
    tool_use = Agents.get_tool_use(tool_id)

    case Agents.deny_tool_use(tool_use, %{denial_reason: reason}) do
      {:ok, _} ->
        pending = Enum.reject(socket.assigns.pending_tools, &(&1.id == tool_id))
        {:noreply, assign(socket, :pending_tools, pending)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to deny")}
    end
  end

  @impl true
  def handle_info({Command.PubSub, :message_created, message}, socket) do
    {:noreply, stream_insert(socket, :messages, message)}
  end

  def handle_info({Command.PubSub, :tool_use_created, tool_use}, socket) do
    if tool_use.requires_approval do
      {:noreply, update(socket, :pending_tools, &[tool_use | &1])}
    else
      {:noreply, socket}
    end
  end

  def handle_info({Command.PubSub, :session_updated, session}, socket) do
    {:noreply, assign(socket, :session, session)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      <%= @session.name %>
      <:subtitle><%= @session.purpose %></:subtitle>
      <:actions>
        <.link patch={~p"/sessions/#{@session}/edit"}>
          <.button>Edit</.button>
        </.link>
      </:actions>
    </.header>

    <div class="mt-6 grid grid-cols-1 lg:grid-cols-4 gap-6">
      <div class="lg:col-span-3">
        <div class="panel">
          <div
            id="messages"
            phx-update="stream"
            class="divide-y divide-slate-100 max-h-[60vh] overflow-y-auto"
          >
            <div
              :for={{dom_id, message} <- @streams.messages}
              id={dom_id}
              class="p-4"
            >
              <.live_component
                module={CommandWorkbenchWeb.SessionLive.MessageComponent}
                id={message.id}
                message={message}
              />
            </div>
          </div>

          <div class="p-4 border-t border-sand-200">
            <.form for={@message_form} phx-submit="send_message" class="flex gap-2">
              <.input
                field={@message_form[:content]}
                type="textarea"
                rows={2}
                placeholder="Type your message..."
                class="flex-1"
              />
              <.button type="submit">Send</.button>
            </.form>
          </div>
        </div>
      </div>

      <div class="space-y-6">
        <div class="panel p-4">
          <h3 class="font-medium mb-3">Session Stats</h3>
          <dl class="space-y-2 text-sm">
            <div class="flex justify-between">
              <dt class="text-slate-500">Messages</dt>
              <dd><%= @session.message_count %></dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-slate-500">Tokens</dt>
              <dd>
                <.token_usage
                  tokens_in={@session.total_tokens_in}
                  tokens_out={@session.total_tokens_out}
                />
              </dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-slate-500">Cost</dt>
              <dd><.cost_display cents={@session.total_cost_cents} /></dd>
            </div>
          </dl>
        </div>

        <div :if={@pending_tools != []} class="panel p-4 border border-amber-200 bg-amber-50">
          <h3 class="font-medium text-amber-800 mb-3">
            Pending Approvals (<%= length(@pending_tools) %>)
          </h3>
          <div class="space-y-3">
            <div :for={tool <- @pending_tools} class="bg-white rounded p-3 text-sm">
              <div class="font-medium"><%= tool.tool_name %></div>
              <pre class="mt-1 text-xs bg-slate-50 p-2 rounded overflow-x-auto">
                <%= Jason.encode!(tool.input, pretty: true) %>
              </pre>
              <div class="mt-2 flex gap-2">
                <.button size="sm" phx-click="approve_tool" phx-value-id={tool.id}>
                  Approve
                </.button>
                <.button
                  size="sm"
                  variant="secondary"
                  phx-click={JS.push("deny_tool", value: %{id: tool.id, reason: "User denied"})}
                >
                  Deny
                </.button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <.modal
      :if={@live_action == :edit}
      id="session-edit-modal"
      show
      on_cancel={JS.patch(~p"/sessions/#{@session}")}
    >
      <.live_component
        module={CommandWorkbenchWeb.SessionLive.FormComponent}
        id={@session.id}
        title="Edit Session"
        action={@live_action}
        session={@session}
        current_user={@current_user}
        patch={~p"/sessions/#{@session}"}
      />
    </.modal>
    """
  end
end
