defmodule Command.Application do
  @moduledoc """
  Command OTP Application.

  Starts the supervision tree and optionally validates portfolio adapters.
  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    _ = Command.Flowstone.ApprovalBridge.attach()

    children =
      [
        Command.Repo,
        Command.Vault,
        {Task.Supervisor, name: Command.TaskSupervisor},
        Command.Orchestration.orchestrator_child_spec(),
        Command.Orchestration.SignalBridge
      ]
      |> Enum.reject(&is_nil/1)

    opts = [strategy: :one_for_one, name: Command.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Validate portfolio adapters after startup (skip in test)
        maybe_validate_adapters()
        {:ok, pid}

      error ->
        error
    end
  end

  defp maybe_validate_adapters do
    # Skip validation in test environment - tests register mocks as needed
    unless Application.get_env(:command, :skip_adapter_validation, false) do
      validate_portfolio_adapters()
    end
  end

  defp validate_portfolio_adapters do
    # Give portfolio_core time to load manifest
    # This is a no-op if adapters aren't configured yet
    if Command.Portfolio.required_adapters_present?() do
      case safe_validate() do
        :ok ->
          Logger.info("[Command] Portfolio adapters validated successfully")

        {:error, reason} ->
          Logger.warning("[Command] Portfolio adapter validation failed: #{inspect(reason)}")
      end
    else
      Logger.debug("[Command] Portfolio adapters not yet registered, skipping validation")
    end
  end

  defp safe_validate do
    Command.Portfolio.validate_adapters!()
  rescue
    e -> {:error, Exception.message(e)}
  end
end
