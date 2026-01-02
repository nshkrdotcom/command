defmodule Command.Repo.Migrations.CreateScheduledJobs do
  use Ecto.Migration

  def change do
    create table(:scheduled_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # What to run
      # "workflow", "reindex", "cleanup", "custom"
      add :job_type, :string, null: false
      add :job_config, :map, null: false
      # For workflow: %{workflow_id: "...", input: %{...}}
      # For reindex: %{index_id: "..."}

      # Schedule
      # "once", "cron", "interval"
      add :schedule_type, :string, null: false
      # For cron type
      add :cron_expression, :string
      # For interval type
      add :interval_seconds, :integer
      # For once type, or next run for recurring
      add :run_at, :utc_datetime_usec
      add :timezone, :string, default: "UTC"

      # Status: active, paused, completed, failed, cancelled
      add :status, :string, default: "active", null: false

      # Execution tracking
      add :last_run_at, :utc_datetime_usec
      add :last_run_status, :string
      add :last_run_error, :text
      add :next_run_at, :utc_datetime_usec

      # Stats
      add :run_count, :integer, default: 0
      add :success_count, :integer, default: 0
      add :failure_count, :integer, default: 0

      # Limits
      # Null = unlimited
      add :max_runs, :integer
      add :expires_at, :utc_datetime_usec

      # Concurrency control
      add :allow_concurrent, :boolean, default: false
      add :currently_running, :boolean, default: false

      # Retry configuration
      add :retry_on_failure, :boolean, default: true
      add :max_retries, :integer, default: 3
      add :retry_delay_seconds, :integer, default: 60

      # Notifications
      add :notify_on_failure, :boolean, default: true
      add :notify_on_success, :boolean, default: false
      add :notification_channels, {:array, :string}, default: []

      # Metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:scheduled_jobs, [:user_id])
    create index(:scheduled_jobs, [:status])
    create index(:scheduled_jobs, [:job_type])
    create index(:scheduled_jobs, [:next_run_at], where: "status = 'active'")
  end
end
