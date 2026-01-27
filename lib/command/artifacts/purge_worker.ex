defmodule Command.Artifacts.PurgeWorker do
  @moduledoc """
  Background worker for hard-deleting expired artifacts after grace period.

  Runs weekly to permanently delete artifacts that have been soft-deleted
  for longer than the grace period (default: 30 days).

  ## Grace Period

  Soft-deleted artifacts are retained for a configurable grace period before
  permanent deletion. This allows recovery if artifacts were deleted in error.

  ## Usage

  Configure in config.exs:

      config :my_app, Oban,
        plugins: [
          {Oban.Plugins.Cron,
           crontab: [
             {"0 3 * * 0", Command.Artifacts.PurgeWorker}  # Weekly on Sunday at 3 AM
           ]}
        ]
  """

  # Uncomment when Oban is available:
  # use Oban.Worker, queue: :artifacts, max_attempts: 3
  #
  # @impl Oban.Worker
  # def perform(%Oban.Job{}) do
  #   Command.Artifacts.Retention.hard_delete_expired()
  # end

  @doc """
  Perform hard deletion of expired artifacts.

  Artifacts that have been soft-deleted for longer than the grace period
  are permanently deleted along with their provenance edges.
  """
  def perform do
    # Placeholder implementation
    # Full implementation would:
    # 1. Query soft-deleted artifacts older than grace period
    # 2. Delete associated provenance edges
    # 3. Delete artifact metadata records
    :ok
  end
end
