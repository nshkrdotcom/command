defmodule Command.Repo.Migrations.CreatePromptRepoResults do
  use Ecto.Migration

  def change do
    create table(:prompt_repo_results, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      # Foreign keys
      add :prompt_step_run_id, references(:prompt_step_runs, type: :uuid, on_delete: :delete_all),
        null: false

      # changeset_id MUST reference the prompt-scoped changeset for this step
      add :changeset_id, references(:prompt_changesets, type: :uuid, on_delete: :nilify_all)

      # Repository identification
      add :repo_name, :string, null: false, size: 255
      add :repo_path, :string, size: 1024

      # Execution status (lifecycle)
      add :status, :string, null: false, default: "pending", size: 50

      # Git results
      # NOTE: VARCHAR(64) supports both SHA-1 (40 chars) and SHA-256 (64 chars) commit hashes
      add :commit_hash, :string, size: 64
      add :commit_status, :string, size: 50
      add :branch_name, :string, size: 255
      add :pr_url, :string, size: 1024

      # Metrics
      add :files_changed, :integer, null: false, default: 0
      add :insertions, :integer, null: false, default: 0
      add :deletions, :integer, null: false, default: 0

      # Error tracking
      add :error_message, :text
      add :error_type, :string, size: 100

      # Timing
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :duration_ms, :integer

      timestamps(type: :utc_datetime_usec)
    end

    # Unique constraint: one result per repo per step
    create unique_index(:prompt_repo_results, [:prompt_step_run_id, :repo_name])

    # Standard indexes
    create index(:prompt_repo_results, [:prompt_step_run_id])

    create index(:prompt_repo_results, [:changeset_id], where: "changeset_id IS NOT NULL")

    create index(:prompt_repo_results, [:repo_name])

    create index(:prompt_repo_results, [:status])

    create index(:prompt_repo_results, [:commit_hash], where: "commit_hash IS NOT NULL")

    # Composite index for recovery/resume queries
    create index(:prompt_repo_results, [:prompt_step_run_id, :status])

    # VALUE DOMAIN CONSTRAINTS: Prevent unknown enum values
    create constraint(:prompt_repo_results, :prompt_repo_results_status_check,
             check: "status IN ('pending', 'running', 'completed', 'failed', 'skipped')"
           )

    create constraint(:prompt_repo_results, :prompt_repo_results_commit_status_check,
             check:
               "commit_status IS NULL OR commit_status IN ('committed', 'no_commit', 'no_changes', 'failed', 'skipped')"
           )

    # CORE INVARIANT: Terminal execution states must have commit outcome; non-terminal must not
    create constraint(:prompt_repo_results, :prompt_repo_results_terminal_commit_status_check,
             check: """
             (status IN ('pending', 'running') AND commit_status IS NULL)
             OR
             (status IN ('completed', 'failed', 'skipped') AND commit_status IS NOT NULL)
             """
           )

    # SEMANTIC ALIGNMENT: Prevents impossible status/commit_status combinations
    create constraint(
             :prompt_repo_results,
             :prompt_repo_results_status_commit_status_alignment_check,
             check: """
             (status IN ('pending', 'running') AND commit_status IS NULL)
             OR
             (status = 'completed' AND commit_status IN ('committed', 'no_commit', 'no_changes'))
             OR
             (status = 'failed' AND commit_status = 'failed')
             OR
             (status = 'skipped' AND commit_status = 'skipped')
             """
           )

    # HASH INVARIANTS: Enforce commit_hash presence/absence based on commit_status
    create constraint(
             :prompt_repo_results,
             :prompt_repo_results_hash_requires_commit_status_check,
             check: "commit_hash IS NULL OR commit_status IS NOT NULL"
           )

    create constraint(:prompt_repo_results, :prompt_repo_results_committed_requires_hash_check,
             check: "commit_status IS DISTINCT FROM 'committed' OR commit_hash IS NOT NULL"
           )

    create constraint(:prompt_repo_results, :prompt_repo_results_no_changes_has_no_hash_check,
             check: "commit_status IS DISTINCT FROM 'no_changes' OR commit_hash IS NULL"
           )

    create constraint(:prompt_repo_results, :prompt_repo_results_no_commit_has_no_hash_check,
             check: "commit_status IS DISTINCT FROM 'no_commit' OR commit_hash IS NULL"
           )

    create constraint(:prompt_repo_results, :prompt_repo_results_skipped_has_no_hash_check,
             check: "commit_status IS DISTINCT FROM 'skipped' OR commit_hash IS NULL"
           )

    # ERROR TRACKING: Failed rows must carry diagnostic context
    create constraint(
             :prompt_repo_results,
             :prompt_repo_results_failed_requires_error_details_check,
             check: """
             status IS DISTINCT FROM 'failed'
             OR (error_message IS NOT NULL AND error_type IS NOT NULL)
             """
           )

    # TIMING: Terminal states should have completion timestamp
    create constraint(
             :prompt_repo_results,
             :prompt_repo_results_terminal_requires_completed_at_check,
             check: "status IN ('pending', 'running') OR completed_at IS NOT NULL"
           )

    # TIMING: Running/terminal states should have start timestamp
    create constraint(
             :prompt_repo_results,
             :prompt_repo_results_running_or_terminal_requires_started_at_check,
             check: "status = 'pending' OR started_at IS NOT NULL"
           )
  end
end
