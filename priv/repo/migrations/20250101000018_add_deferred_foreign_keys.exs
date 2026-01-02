defmodule Command.Repo.Migrations.AddDeferredForeignKeys do
  use Ecto.Migration

  def change do
    # Add foreign keys that were deferred due to table creation order

    # messages.agent_call_id -> agent_calls
    alter table(:messages) do
      modify :agent_call_id, references(:agent_calls, type: :binary_id, on_delete: :nilify_all),
        from: :binary_id
    end

    # messages.tool_use_id -> tool_uses
    alter table(:messages) do
      modify :tool_use_id, references(:tool_uses, type: :binary_id, on_delete: :nilify_all),
        from: :binary_id
    end

    # sessions.forked_at_message_id -> messages
    alter table(:sessions) do
      modify :forked_at_message_id,
             references(:messages, type: :binary_id, on_delete: :nilify_all),
             from: :binary_id
    end

    # agent_calls.workflow_run_id -> workflow_runs
    alter table(:agent_calls) do
      modify :workflow_run_id,
             references(:workflow_runs, type: :binary_id, on_delete: :nilify_all),
             from: :binary_id
    end

    # agent_calls.workflow_step_id -> workflow_steps
    alter table(:agent_calls) do
      modify :workflow_step_id,
             references(:workflow_steps, type: :binary_id, on_delete: :nilify_all),
             from: :binary_id
    end

    # tool_uses.approval_id -> approval_items
    alter table(:tool_uses) do
      modify :approval_id, references(:approval_items, type: :binary_id, on_delete: :nilify_all),
        from: :binary_id
    end

    # workflow_steps.approval_id -> approval_items
    alter table(:workflow_steps) do
      modify :approval_id, references(:approval_items, type: :binary_id, on_delete: :nilify_all),
        from: :binary_id
    end

    # approval_rules.auto_approval_rule_id reference was self-referential, skip

    # cost_records.workflow_run_id -> workflow_runs
    alter table(:cost_records) do
      modify :workflow_run_id,
             references(:workflow_runs, type: :binary_id, on_delete: :nilify_all),
             from: :binary_id
    end

    # Add additional indexes for common query patterns (using inserted_at, not created_at)
    create index(:agent_calls, [:session_id, :inserted_at])
    create index(:tool_uses, [:session_id, :inserted_at])
    create index(:messages, [:session_id, :inserted_at])

    # Add unique constraints
    create unique_index(:context_documents, [:index_id, :uri, :git_commit],
             where: "git_commit IS NOT NULL",
             name: :context_documents_uri_commit_idx
           )
  end
end
