defmodule CommandWorkbenchWeb.CommandComponents do
  @moduledoc false
  use CommandWorkbenchWeb, :html

  alias Command.Phoenix.Components

  attr(:status, :string, required: true)
  attr(:class, :string, default: nil)

  def session_status(assigns) do
    assigns = assign_new(assigns, :class, fn -> "status-pill" end)
    Components.session_status(assigns)
  end

  attr(:status, :string, required: true)
  attr(:class, :string, default: nil)

  def approval_status(assigns) do
    assigns = assign_new(assigns, :class, fn -> "status-pill" end)
    Components.approval_status(assigns)
  end

  attr(:cents, :integer, required: true)
  attr(:class, :string, default: nil)

  def cost_display(assigns) do
    assigns = assign_new(assigns, :class, fn -> "cost-pill" end)
    Components.cost_display(assigns)
  end

  attr(:tokens_in, :integer, required: true)
  attr(:tokens_out, :integer, required: true)
  attr(:class, :string, default: nil)

  def token_usage(assigns) do
    assigns = assign_new(assigns, :class, fn -> "token-pill" end)
    Components.token_usage(assigns)
  end

  attr(:message, :map, required: true)
  attr(:class, :string, default: nil)
  slot(:inner_block)

  def message(assigns) do
    assigns = assign_new(assigns, :class, fn -> "message-card" end)
    Components.message(assigns)
  end
end
