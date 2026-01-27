defmodule Command.Artifacts.RetentionWorker do
  @moduledoc """
  Background worker for soft-deleting expired artifacts.

  Runs daily to identify artifacts that have exceeded their retention period
  and marks them as soft-deleted (sets deleted_at timestamp).

  ## Retention Policy

  Artifacts are expired based on their type's retention_days:
  - Prompts: indefinite
  - Responses: 365 days
  - Transcripts: 90 days
  - Diffs: 365 days
  - etc.

  Artifacts with provenance edges of type `released_in`, `implements`, or
  related to approvals are **pinned** and excluded from automatic deletion.

  ## Usage

  If using Oban:

      defmodule MyApp.Application do
        def start(_type, _args) do
          children = [
            {Oban, oban_config()},
            # ...
          ]
        end

        defp oban_config do
          Application.fetch_env!(:my_app, Oban)
        end
      end

  Configure in config.exs:

      config :my_app, Oban,
        repo: MyApp.Repo,
        plugins: [
          {Oban.Plugins.Cron,
           crontab: [
             {"0 2 * * *", Command.Artifacts.RetentionWorker}  # Daily at 2 AM
           ]}
        ],
        queues: [artifacts: 10]
  """

  # Uncomment when Oban is available:
  # use Oban.Worker, queue: :artifacts, max_attempts: 3
  #
  # @impl Oban.Worker
  # def perform(%Oban.Job{}) do
  #   Command.Artifacts.Retention.soft_delete_expired()
  # end

  @doc """
  Perform retention cleanup (soft delete expired artifacts).

  This function can be called directly for testing or manual execution.
  In production, it would be called by Oban.
  """
  def perform do
    # Placeholder implementation
    # Full implementation would:
    # 1. Query artifacts past their retention period
    # 2. Exclude pinned artifacts (with released_in/implements/approval edges)
    # 3. Mark as soft-deleted (set deleted_at)
    # 4. Delete content files for non-deduplicated types
    :ok
  end
end
