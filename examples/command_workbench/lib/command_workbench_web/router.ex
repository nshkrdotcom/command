defmodule CommandWorkbenchWeb.Router do
  use CommandWorkbenchWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {CommandWorkbenchWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:assign_current_user)
  end

  scope "/", CommandWorkbenchWeb do
    pipe_through(:browser)

    live("/", DashboardLive, :index)

    # Sessions
    live("/sessions", SessionLive.Index, :index)
    live("/sessions/new", SessionLive.Index, :new)
    live("/sessions/:id", SessionLive.Show, :show)
    live("/sessions/:id/edit", SessionLive.Show, :edit)

    # Approvals
    live("/approvals", ApprovalLive.Index, :index)
    live("/approvals/:id", ApprovalLive.Show, :show)

    # Workflows
    live("/workflows", WorkflowLive.Index, :index)
    live("/workflows/new", WorkflowLive.Index, :new)
    live("/workflows/:id", WorkflowLive.Show, :show)
    live("/workflows/:id/runs/:run_id", WorkflowLive.Show, :run)

    # Costs
    live("/costs", CostLive.Dashboard, :index)
  end

  if Application.compile_env(:command_workbench, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)
      live_dashboard("/dashboard", metrics: CommandWorkbenchWeb.Telemetry)
    end
  end

  defp assign_current_user(conn, _opts) do
    case conn.assigns[:current_user] do
      %{} = user ->
        assign(conn, :current_user, user)

      _ ->
        assign(conn, :current_user, get_or_create_demo_user())
    end
  end

  defp get_or_create_demo_user do
    case Command.Accounts.get_user_by_email("demo@example.com") do
      nil ->
        {:ok, user} =
          Command.Accounts.create_user(%{
            email: "demo@example.com",
            name: "Demo User"
          })

        user

      user ->
        user
    end
  end
end
