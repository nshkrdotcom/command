defmodule Command.Repo.Migrations.CreatePromptChangesets do
  use Ecto.Migration

  def change do
    create table(:prompt_changesets, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      # Scope: determines which FK columns must be set
      # 'prompt' -> prompt_step_run_id required
      # 'run' -> prompt_set_run_id required, prompt_step_run_id NULL
      # 'workspace' -> both FKs NULL
      add :scope, :string, null: false, default: "prompt", size: 20

      # Foreign keys (presence governed by scope)
      add :prompt_set_run_id, references(:prompt_set_runs, type: :uuid, on_delete: :delete_all)
      add :prompt_step_run_id, references(:prompt_step_runs, type: :uuid, on_delete: :delete_all)

      # Hierarchy: prompt-level changesets can have a parent run-level changeset
      add :parent_changeset_id,
          references(:prompt_changesets, type: :uuid, on_delete: :nilify_all)

      # Changeset identity
      add :name, :string, size: 255
      add :description, :text

      # Aggregate status
      add :status, :string, null: false, default: "pending", size: 50

      # Cached counters (updated transactionally when prompt_repo_results change)
      add :repos_total, :integer, null: false, default: 0
      add :repos_completed, :integer, null: false, default: 0
      add :repos_failed, :integer, null: false, default: 0

      # Branch coordination
      add :branch_name, :string, size: 255

      # PR management (informational - Forge integration is optional/future)
      add :pr_urls, :jsonb, null: false, default: "[]"

      # Summary (generated after completion)
      add :summary, :text
      add :summary_generated_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    # Partial unique index for run scope - one run-level changeset per prompt_set_run
    create unique_index(:prompt_changesets, [:prompt_set_run_id],
             where: "scope = 'run' AND prompt_set_run_id IS NOT NULL",
             name: :idx_prompt_changesets_unique_run
           )

    # Partial unique index for prompt scope - one prompt-level changeset per step
    create unique_index(:prompt_changesets, [:prompt_step_run_id],
             where: "scope = 'prompt' AND prompt_step_run_id IS NOT NULL",
             name: :idx_prompt_changesets_unique_step
           )

    # Standard indexes
    create index(:prompt_changesets, [:prompt_set_run_id], where: "prompt_set_run_id IS NOT NULL")

    create index(:prompt_changesets, [:prompt_step_run_id],
             where: "prompt_step_run_id IS NOT NULL"
           )

    create index(:prompt_changesets, [:parent_changeset_id],
             where: "parent_changeset_id IS NOT NULL"
           )

    create index(:prompt_changesets, [:status])

    create index(:prompt_changesets, [:branch_name], where: "branch_name IS NOT NULL")

    # Scope constraint
    create constraint(:prompt_changesets, :prompt_changesets_scope_check,
             check: "scope IN ('prompt', 'run', 'workspace')"
           )

    # Status constraint
    create constraint(:prompt_changesets, :prompt_changesets_status_check,
             check:
               "status IN ('pending', 'in_progress', 'completed', 'partial_success', 'failed', 'rolled_back')"
           )

    # Scope-FK invariants: enforce which FKs must be present based on scope
    create constraint(:prompt_changesets, :prompt_changesets_scope_fk_check,
             check: """
             CASE scope
               WHEN 'prompt' THEN prompt_step_run_id IS NOT NULL
               WHEN 'run' THEN prompt_set_run_id IS NOT NULL AND prompt_step_run_id IS NULL
               WHEN 'workspace' THEN prompt_set_run_id IS NULL AND prompt_step_run_id IS NULL
             END
             """
           )
  end
end
