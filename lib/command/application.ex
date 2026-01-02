defmodule Command.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Command.Repo,
      Command.Vault,
      {Task.Supervisor, name: Command.TaskSupervisor}
    ]

    opts = [strategy: :one_for_one, name: Command.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
