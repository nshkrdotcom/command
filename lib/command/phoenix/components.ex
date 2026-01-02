defmodule Command.Phoenix.Components do
  @moduledoc """
  Phoenix component helpers for Command UI elements.

  These are headless components that provide data and behavior
  without styling, designed to be wrapped by your own styled components.
  """

  use Phoenix.Component

  @doc """
  Renders session status with appropriate styling hooks.

  ## Examples

      <.session_status status={@session.status} />
  """
  attr(:status, :string, required: true)
  attr(:class, :string, default: nil)

  def session_status(assigns) do
    ~H"""
    <span class={[@class, status_class(@status)]} data-status={@status}>
      <%= status_label(@status) %>
    </span>
    """
  end

  defp status_class("active"), do: "status-active"
  defp status_class("paused"), do: "status-paused"
  defp status_class("completed"), do: "status-completed"
  defp status_class("archived"), do: "status-archived"
  defp status_class(_), do: "status-unknown"

  defp status_label("active"), do: "Active"
  defp status_label("paused"), do: "Paused"
  defp status_label("completed"), do: "Completed"
  defp status_label("archived"), do: "Archived"
  defp status_label(other), do: other

  @doc """
  Renders an approval status badge.
  """
  attr(:status, :string, required: true)
  attr(:class, :string, default: nil)

  def approval_status(assigns) do
    ~H"""
    <span class={[@class, approval_class(@status)]} data-approval-status={@status}>
      <%= approval_label(@status) %>
    </span>
    """
  end

  defp approval_class("pending"), do: "approval-pending"
  defp approval_class("approved"), do: "approval-approved"
  defp approval_class("denied"), do: "approval-denied"
  defp approval_class("auto_approved"), do: "approval-auto"
  defp approval_class("expired"), do: "approval-expired"
  defp approval_class(_), do: "approval-unknown"

  defp approval_label("pending"), do: "Pending"
  defp approval_label("approved"), do: "Approved"
  defp approval_label("denied"), do: "Denied"
  defp approval_label("auto_approved"), do: "Auto-approved"
  defp approval_label("expired"), do: "Expired"
  defp approval_label(other), do: other

  @doc """
  Renders a cost display with formatting.
  """
  attr(:cents, :integer, required: true)
  attr(:class, :string, default: nil)

  def cost_display(assigns) do
    ~H"""
    <span class={@class} data-cents={@cents}>
      $<%= format_cost(@cents) %>
    </span>
    """
  end

  defp format_cost(cents) when is_integer(cents) do
    dollars = cents / 100
    :erlang.float_to_binary(dollars, decimals: 2)
  end

  @doc """
  Renders token usage display.
  """
  attr(:tokens_in, :integer, required: true)
  attr(:tokens_out, :integer, required: true)
  attr(:class, :string, default: nil)

  def token_usage(assigns) do
    ~H"""
    <span class={@class}>
      <span class="tokens-in" title="Input tokens"><%= format_tokens(@tokens_in) %> in</span>
      <span class="tokens-separator">/</span>
      <span class="tokens-out" title="Output tokens"><%= format_tokens(@tokens_out) %> out</span>
    </span>
    """
  end

  defp format_tokens(tokens) when tokens >= 1_000_000 do
    "#{Float.round(tokens / 1_000_000, 1)}M"
  end

  defp format_tokens(tokens) when tokens >= 1_000 do
    "#{Float.round(tokens / 1_000, 1)}K"
  end

  defp format_tokens(tokens), do: "#{tokens}"

  @doc """
  Renders a message in a conversation.
  """
  attr(:message, :map, required: true)
  attr(:class, :string, default: nil)
  slot(:inner_block)

  def message(assigns) do
    ~H"""
    <div class={[@class, "message", "message-#{@message.role}"]} data-role={@message.role}>
      <div class="message-role"><%= role_label(@message.role) %></div>
      <div class="message-content">
        <%= if @inner_block do %>
          <%= render_slot(@inner_block) %>
        <% else %>
          <%= @message.content %>
        <% end %>
      </div>
    </div>
    """
  end

  defp role_label("user"), do: "You"
  defp role_label("assistant"), do: "Assistant"
  defp role_label("system"), do: "System"
  defp role_label("tool_result"), do: "Tool"
  defp role_label(other), do: other
end
