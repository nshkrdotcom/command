defmodule Command.Repo.Migrations.CreatePromptSetRuns do
  use Ecto.Migration

  def change do
    create table(:prompt_set_runs, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      # Foreign keys
      add :prompt_set_id, references(:prompt_sets, type: :uuid, on_delete: :restrict), null: false

      # Optional FK to pipeline runs - use if_exists to handle missing table gracefully
      add :pipeline_run_id, :uuid

      # Execution state
      add :status, :string, null: false, default: "pending", size: 50
      add :current_prompt, :string, size: 10
      add :last_completed_prompt, :string, size: 10

      # Branch strategy (snapshot from config at execution time)
      add :branch_name, :string, size: 255
      add :branch_strategy, :string, size: 50

      # Configuration snapshot (captures config at execution time)
      add :config_snapshot, :jsonb, null: false, default: "{}"

      # Timing
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      # Aggregate metrics (denormalized for query performance)
      add :total_prompts, :integer, null: false, default: 0
      add :completed_prompts, :integer, null: false, default: 0
      add :failed_prompts, :integer, null: false, default: 0
      add :total_input_tokens, :integer, null: false, default: 0
      add :total_output_tokens, :integer, null: false, default: 0
      add :total_cost_usd, :decimal, precision: 12, scale: 6, null: false, default: 0

      # Error summary (if run failed)
      add :error_summary, :text

      timestamps(type: :utc_datetime_usec)
    end

    # Index for prompt set queries
    create index(:prompt_set_runs, [:prompt_set_id])

    # Index for status queries
    create index(:prompt_set_runs, [:status])

    # Composite index for prompt set + status
    create index(:prompt_set_runs, [:prompt_set_id, :status])

    # Index for recent runs (dashboard queries)
    create index(:prompt_set_runs, [:started_at], where: "started_at IS NOT NULL")

    # Status check constraint (includes partial_success for multi-repo support)
    create constraint(:prompt_set_runs, :prompt_set_runs_status_check,
             check:
               "status IN ('pending', 'running', 'paused', 'completed', 'partial_success', 'failed', 'aborted')"
           )

    # Add FK to pipeline runs if table exists
    execute(
      """
      DO $$
      BEGIN
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'command_pipeline_runs') THEN
          ALTER TABLE prompt_set_runs
            ADD CONSTRAINT prompt_set_runs_pipeline_run_id_fkey
            FOREIGN KEY (pipeline_run_id)
            REFERENCES command_pipeline_runs(id)
            ON DELETE SET NULL;
        END IF;
      END $$;
      """,
      """
      ALTER TABLE prompt_set_runs DROP CONSTRAINT IF EXISTS prompt_set_runs_pipeline_run_id_fkey;
      """
    )
  end
end
