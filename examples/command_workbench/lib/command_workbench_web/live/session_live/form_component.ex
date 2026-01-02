defmodule CommandWorkbenchWeb.SessionLive.FormComponent do
  use CommandWorkbenchWeb, :live_component

  alias Command.Sessions

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
      </.header>

      <.simple_form
        for={@form}
        id="session-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:purpose]} type="textarea" label="Purpose" />
        <.input
          field={@form[:default_agent]}
          type="select"
          label="Default Agent"
          options={[{"Claude", "claude"}, {"Codex", "codex"}, {"Gemini", "gemini"}]}
        />
        <.input
          field={@form[:default_model]}
          type="text"
          label="Default Model"
          placeholder="claude-sonnet-4-20250514"
        />
        <.input
          field={@form[:system_prompt]}
          type="textarea"
          label="System Prompt"
          rows={4}
        />
        <:actions>
          <.button phx-disable-with="Saving...">Save Session</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{session: session} = assigns, socket) do
    changeset = Sessions.change_session(session)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"session" => session_params}, socket) do
    changeset =
      socket.assigns.session
      |> Sessions.change_session(session_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"session" => session_params}, socket) do
    save_session(socket, socket.assigns.action, session_params)
  end

  defp save_session(socket, :new, session_params) do
    user = socket.assigns.current_user

    case Sessions.create_session(user, session_params) do
      {:ok, session} ->
        notify_parent({:saved, session})

        {:noreply,
         socket
         |> put_flash(:info, "Session created")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_session(socket, :edit, session_params) do
    case Sessions.update_session_config(socket.assigns.session, session_params) do
      {:ok, session} ->
        notify_parent({:saved, session})

        {:noreply,
         socket
         |> put_flash(:info, "Session updated")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
