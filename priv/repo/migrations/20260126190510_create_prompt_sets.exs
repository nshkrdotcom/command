defmodule Command.Repo.Migrations.CreatePromptSets do
  use Ecto.Migration

  def change do
    create table(:prompt_sets, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      # Identity
      add :name, :string, null: false, size: 255
      add :slug, :string, null: false, size: 255

      # Document Set Reference (optional)
      add :doc_set_id, :string, size: 255
      add :doc_set_version, :string, size: 50

      # JSONB fields
      # prompts: array of {num, phase, sp, name, file, provider?, model?, tools?,
      #                    target_repos?, execution_mode?, permission_mode?,
      #                    claude_opts?, codex_opts?, codex_thread_opts?}
      add :prompts, :jsonb, null: false, default: "[]"

      # commit_messages: map of prompt_num -> commit message text
      add :commit_messages, :jsonb, null: false, default: "{}"

      # phase_names: map of phase_num -> phase name
      add :phase_names, :jsonb, null: false, default: "{}"

      # config: {project_dir, target_repos, prompts_dir, log_dir, default_model,
      #          default_provider, allowed_tools, permission_mode, log_mode,
      #          log_meta, events_mode, auto_commit, cost_ceiling_usd, workspace_root}
      add :config, :jsonb, null: false, default: "{}"

      # Lifecycle
      add :status, :string, null: false, default: "active", size: 50

      timestamps(type: :utc_datetime_usec)
    end

    # Unique constraint on slug
    create unique_index(:prompt_sets, [:slug])

    # Index for doc set queries
    create index(:prompt_sets, [:doc_set_id, :doc_set_version], where: "doc_set_id IS NOT NULL")

    # Index for active sets
    create index(:prompt_sets, [:status], where: "status = 'active'")

    # Check constraint for status
    create constraint(:prompt_sets, :prompt_sets_status_check,
             check: "status IN ('active', 'archived', 'draft')"
           )
  end
end
