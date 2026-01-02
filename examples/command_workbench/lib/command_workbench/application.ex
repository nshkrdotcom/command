defmodule CommandWorkbench.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CommandWorkbenchWeb.Telemetry,
      {Phoenix.PubSub, name: CommandWorkbench.PubSub},
      CommandWorkbenchWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: CommandWorkbench.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    CommandWorkbenchWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
