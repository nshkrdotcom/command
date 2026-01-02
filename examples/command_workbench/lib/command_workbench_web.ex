defmodule CommandWorkbenchWeb do
  @moduledoc false

  def controller do
    quote do
      use Phoenix.Controller,
        namespace: CommandWorkbenchWeb,
        formats: [:html],
        layouts: [html: CommandWorkbenchWeb.Layouts]

      import Plug.Conn
      import CommandWorkbenchWeb.CoreComponents
      import CommandWorkbenchWeb.CommandComponents
      unquote(html_helpers())
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {CommandWorkbenchWeb.Layouts, :app}

      import CommandWorkbenchWeb.CoreComponents
      import CommandWorkbenchWeb.CommandComponents
      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      import CommandWorkbenchWeb.CoreComponents
      import CommandWorkbenchWeb.CommandComponents
      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import CommandWorkbenchWeb.CoreComponents
      import CommandWorkbenchWeb.CommandComponents
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      import Phoenix.HTML
      alias Phoenix.LiveView.JS

      use Phoenix.VerifiedRoutes,
        endpoint: CommandWorkbenchWeb.Endpoint,
        router: CommandWorkbenchWeb.Router,
        statics: CommandWorkbenchWeb.static_paths()
    end
  end

  def static_paths do
    ~w(assets fonts images favicon.ico robots.txt)
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
