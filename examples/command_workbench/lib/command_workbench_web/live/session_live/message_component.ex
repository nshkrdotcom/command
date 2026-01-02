defmodule CommandWorkbenchWeb.SessionLive.MessageComponent do
  use CommandWorkbenchWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <.message message={@message} class={message_class(@message.role)}>
      <:inner_block>
        <div class="message-text"><%= @message.content %></div>
      </:inner_block>
    </.message>
    """
  end

  defp message_class("user"), do: "message-user"
  defp message_class("assistant"), do: "message-assistant"
  defp message_class("system"), do: "message-system"
  defp message_class("tool_result"), do: "message-tool"
  defp message_class(_), do: "message-generic"
end
