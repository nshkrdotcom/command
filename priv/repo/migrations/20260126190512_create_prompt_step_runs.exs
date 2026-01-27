defmodule Command.Repo.Migrations.CreatePromptStepRuns do
  use Ecto.Migration

  def change do
    create table(:prompt_step_runs, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      # Foreign key
      add :prompt_set_run_id, references(:prompt_set_runs, type: :uuid, on_delete: :delete_all),
        null: false

      # Identity
      add :prompt_num, :string, null: false, size: 10

      # Execution state
      add :status, :string, null: false, default: "pending", size: 50

      # Provider details
      add :provider, :string, size: 50
      add :model, :string, size: 255

      # Git integration (single-repo legacy)
      # NOTE: VARCHAR(64) supports both SHA-1 (40 chars) and SHA-256 (64 chars) commit hashes
      add :commit_hash, :string, size: 64
      add :commit_status, :string, size: 50

      # Git integration (multi-repo) - DEPRECATED, use prompt_repo_results instead
      add :target_repo, :string, size: 255
      add :commit_hashes, :jsonb, null: false, default: "[]"

      # Usage metrics
      add :input_tokens, :integer, null: false, default: 0
      add :output_tokens, :integer, null: false, default: 0
      add :cost_usd, :decimal, precision: 10, scale: 6, null: false, default: 0

      # Duration
      add :duration_ms, :integer

      # Artifact references (soft FK, not enforced)
      add :log_artifact_id, :uuid
      add :events_artifact_id, :uuid

      # Error tracking
      add :error_message, :text
      add :error_type, :string, size: 100
      add :retry_count, :integer, null: false, default: 0

      # Timing
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    # Unique constraint on (run_id, prompt_num)
    create unique_index(:prompt_step_runs, [:prompt_set_run_id, :prompt_num])

    # Index for status queries
    create index(:prompt_step_runs, [:status])

    # Composite index for run + status
    create index(:prompt_step_runs, [:prompt_set_run_id, :status])

    # Index for commit hash queries (lineage tracking)
    create index(:prompt_step_runs, [:commit_hash], where: "commit_hash IS NOT NULL")

    # Index for error analysis
    create index(:prompt_step_runs, [:error_type], where: "error_type IS NOT NULL")

    # Index for multi-repo queries by target repository
    create index(:prompt_step_runs, [:prompt_set_run_id, :target_repo],
             where: "target_repo IS NOT NULL"
           )

    # GIN index for commit_hashes JSONB queries
    create index(:prompt_step_runs, [:commit_hashes],
             using: "GIN",
             where: "commit_hashes != '[]'::jsonb"
           )

    # Status check constraint (includes partial_success)
    create constraint(:prompt_step_runs, :prompt_step_runs_status_check,
             check:
               "status IN ('pending', 'running', 'completed', 'partial_success', 'failed', 'skipped')"
           )

    # Commit status check constraint
    create constraint(:prompt_step_runs, :prompt_step_runs_commit_status_check,
             check:
               "commit_status IS NULL OR commit_status IN ('committed', 'no_commit', 'no_changes', 'failed', 'skipped')"
           )
  end
end
