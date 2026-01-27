defmodule Command.Artifacts.CasGcWorker do
  @moduledoc """
  Background worker for garbage collecting unreferenced CAS content.

  Runs weekly (after PurgeWorker) to remove content files that are no longer
  referenced by any active artifacts.

  ## Algorithm

  1. Query all content hashes referenced by active artifacts
  2. Walk the `artifacts/content/` directory tree
  3. Delete any files whose hash is not in the referenced set
  4. Prune empty hash-prefix directories

  ## Usage

  Configure in config.exs:

      config :my_app, Oban,
        plugins: [
          {Oban.Plugins.Cron,
           crontab: [
             {"0 4 * * 0", Command.Artifacts.CasGcWorker}  # Weekly on Sunday at 4 AM
           ]}
        ]
  """

  # Uncomment when Oban is available:
  # use Oban.Worker, queue: :artifacts, max_attempts: 3
  #
  # @impl Oban.Worker
  # def perform(%Oban.Job{}) do
  #   Command.Artifacts.Retention.gc_unreferenced_content()
  # end

  @doc """
  Perform CAS garbage collection.

  Removes content files that are no longer referenced by any artifacts.
  """
  def perform do
    # Placeholder implementation
    # Full implementation would:
    # 1. SELECT DISTINCT content_hash FROM artifacts WHERE deleted_at IS NULL
    # 2. Walk artifacts/content/** directory
    # 3. Delete files not in referenced set
    # 4. Remove empty prefix directories
    :ok
  end
end
