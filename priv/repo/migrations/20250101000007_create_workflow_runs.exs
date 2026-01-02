defmodule Command.Repo.Migrations.CreateWorkflowRuns do
  use Ecto.Migration

  def change do
    create table(:workflow_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workflow_id, references(:workflows, type: :binary_id, on_delete: :nilify_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Optional: tie to a session for context/history
      add :session_id, references(:sessions, type: :binary_id, on_delete: :nilify_all)

      # Snapshot of workflow definition at run time (in case workflow changes)
      add :workflow_snapshot, :map, null: false

      # Status: pending, running, paused, waiting_approval, completed, failed, cancelled, timeout
      add :status, :string, default: "pending", null: false

      # Input parameters for this run
      add :input, :map, default: %{}

      # Output/result of the workflow
      add :output, :map, default: %{}

      # Current execution state
      add :current_step_id, :string
      add :completed_step_ids, {:array, :string}, default: []
      add :failed_step_id, :string

      # Timing
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :duration_ms, :bigint

      # Cost tracking (aggregated from agent calls)
      add :total_tokens_in, :bigint, default: 0
      add :total_tokens_out, :bigint, default: 0
      add :total_cost_cents, :integer, default: 0

      # Trigger info (what started this run?)
      # "manual", "schedule", "webhook", "api"
      add :trigger_type, :string
      add :trigger_metadata, :map, default: %{}

      # Error tracking
      add :error_type, :string
      add :error_message, :text
      add :error_step_id, :string

      # Git context for this specific run
      add :git_context, :map, default: %{}

      # Retry tracking
      add :retry_of_run_id, references(:workflow_runs, type: :binary_id, on_delete: :nilify_all)
      add :retry_count, :integer, default: 0

      # Metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:workflow_runs, [:workflow_id])
    create index(:workflow_runs, [:user_id])
    create index(:workflow_runs, [:session_id])
    create index(:workflow_runs, [:status])
    create index(:workflow_runs, [:trigger_type])
    create index(:workflow_runs, [:inserted_at])
    create index(:workflow_runs, [:user_id, :inserted_at])
  end
end
