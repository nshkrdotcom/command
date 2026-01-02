defmodule CommandWorkbenchWeb.CoreComponents do
  @moduledoc false
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @doc """
  Renders a header with optional actions.
  """
  slot(:inner_block, required: true)
  slot(:actions)
  slot(:subtitle)

  def header(assigns) do
    ~H"""
    <header class="page-header">
      <div>
        <h1 class="page-title"><%= render_slot(@inner_block) %></h1>
        <p :if={@subtitle != []} class="page-subtitle"><%= render_slot(@subtitle) %></p>
      </div>
      <div :if={@actions != []} class="page-actions">
        <%= render_slot(@actions) %>
      </div>
    </header>
    """
  end

  @doc """
  Renders a navigation link.
  """
  attr(:to, :string, required: true)
  attr(:label, :string, required: true)

  def nav_link(assigns) do
    ~H"""
    <.link navigate={@to} class="nav-link"><%= @label %></.link>
    """
  end

  @doc """
  Renders a table with streamed rows.
  """
  attr(:id, :string, required: true)
  attr(:rows, :list, required: true)
  attr(:row_click, :any, default: nil)

  slot :col, required: true do
    attr(:label, :string)
  end

  slot(:action)

  def table(assigns) do
    ~H"""
    <div class="table-wrap">
      <table id={@id} class="table">
        <thead>
          <tr>
            <th :for={col <- @col}><%= col[:label] %></th>
            <th :if={@action != []}></th>
          </tr>
        </thead>
        <tbody id={@id <> "-body"}>
          <tr
            :for={row <- @rows}
            id={row_id(row)}
            class={[@row_click && "is-clickable"]}
            phx-click={@row_click && @row_click.(row)}
          >
            <td :for={col <- @col}><%= render_slot(col, row) %></td>
            <td :if={@action != []} class="table-actions">
              <%= render_slot(@action, row) %>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a button.
  """
  attr(:type, :string, default: "button")
  attr(:variant, :string, default: "primary")
  attr(:size, :string, default: "md")
  attr(:class, :string, default: nil)

  attr(:rest, :global,
    include: ~w(disabled form name value phx-click phx-disable-with phx-target)
  )

  slot(:inner_block, required: true)

  def button(assigns) do
    ~H"""
    <button type={@type} class={[button_class(@variant, @size), @class]} {@rest}>
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  @doc """
  Renders flash messages.
  """
  attr(:flash, :map, required: true)

  def flash_group(assigns) do
    ~H"""
    <div class="flash-group" role="status" aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end

  attr(:kind, :atom, required: true)
  attr(:flash, :map, required: true)

  def flash(assigns) do
    ~H"""
    <div :if={msg = Phoenix.Flash.get(@flash, @kind)} class={["flash", "flash-#{@kind}"]}>
      <span><%= msg %></span>
    </div>
    """
  end

  @doc """
  Simple form wrapper for inputs.
  """
  attr(:for, :any, required: true)
  attr(:as, :any, default: nil)
  attr(:rest, :global, include: ~w(id phx-change phx-submit phx-target autocomplete))

  slot(:inner_block, required: true)
  slot(:actions)

  def simple_form(assigns) do
    ~H"""
    <.form for={@for} as={@as} class="form" {@rest}>
      <div class="form-body">
        <%= render_slot(@inner_block) %>
      </div>
      <div :if={@actions != []} class="form-actions">
        <%= render_slot(@actions) %>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a form input with label and errors.
  """
  attr(:field, Phoenix.HTML.FormField, required: true)
  attr(:type, :string, default: "text")
  attr(:label, :string, default: nil)
  attr(:options, :list, default: [])
  attr(:value, :any, default: nil)
  attr(:class, :string, default: nil)
  attr(:rest, :global, include: ~w(placeholder rows min max step autocomplete))

  def input(assigns) do
    assigns =
      assigns
      |> assign_new(:id, fn -> assigns.field.id end)
      |> assign_new(:name, fn -> assigns.field.name end)
      |> assign_new(:value, fn -> assigns.value || assigns.field.value end)

    ~H"""
    <div class="form-field">
      <label :if={@label} for={@id} class="form-label"><%= @label %></label>
      <div class="form-input">
        <%= case @type do %>
          <% "textarea" -> %>
            <textarea
              id={@id}
              name={@name}
              class={[input_class(@type), @class]}
              {@rest}
            ><%= @value %></textarea>
          <% "select" -> %>
            <select id={@id} name={@name} class={[input_class(@type), @class]} {@rest}>
              <option :for={{label, value} <- @options} value={value} selected={value == @value}>
                <%= label %>
              </option>
            </select>
          <% _ -> %>
            <input
              id={@id}
              name={@name}
              type={@type}
              value={@value}
              class={[input_class(@type), @class]}
              {@rest}
            />
        <% end %>
      </div>
      <.error :for={msg <- @field.errors}><%= translate_error(msg) %></.error>
    </div>
    """
  end

  @doc """
  Renders a modal dialog.
  """
  attr(:id, :string, required: true)
  attr(:show, :boolean, default: false)
  attr(:on_cancel, JS, default: %JS{})
  slot(:inner_block, required: true)

  def modal(assigns) do
    ~H"""
    <div id={@id} class="modal" phx-mounted={@show && show_modal(@id)} phx-remove={hide_modal(@id)}>
      <div class="modal-backdrop" phx-click={@on_cancel}></div>
      <div class="modal-panel" phx-click-away={@on_cancel}>
        <button type="button" class="modal-close" phx-click={@on_cancel} aria-label="Close">
          Close
        </button>
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  @doc """
  Shows a modal via JS.
  """
  def show_modal(js \\ %JS{}, id) do
    js
    |> JS.show(to: "##{id}", display: "flex")
    |> JS.add_class("no-scroll", to: "body")
  end

  @doc """
  Hides a modal via JS.
  """
  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(to: "##{id}")
    |> JS.remove_class("no-scroll", to: "body")
  end

  defp row_id({id, _row}), do: id
  defp row_id(row), do: row.id

  defp button_class("primary", "sm"), do: "btn btn-primary btn-sm"
  defp button_class("primary", _), do: "btn btn-primary"
  defp button_class("secondary", "sm"), do: "btn btn-secondary btn-sm"
  defp button_class("secondary", _), do: "btn btn-secondary"
  defp button_class("ghost", "sm"), do: "btn btn-ghost btn-sm"
  defp button_class("ghost", _), do: "btn btn-ghost"
  defp button_class(_, size), do: button_class("primary", size)

  defp input_class("textarea"), do: "input textarea"
  defp input_class("select"), do: "input select"
  defp input_class(_), do: "input"

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp translate_error(msg), do: msg

  slot(:inner_block, required: true)

  def error(assigns) do
    ~H"""
    <p class="form-error"><%= render_slot(@inner_block) %></p>
    """
  end
end
