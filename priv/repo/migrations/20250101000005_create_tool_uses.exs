defmodule Command.Repo.Migrations.CreateToolUses do
  use Ecto.Migration

  def change do
    create table(:tool_uses, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :agent_call_id, references(:agent_calls, type: :binary_id, on_delete: :delete_all),
        null: false

      add :session_id, references(:sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      # Tool identification
      # "bash", "write_file", "read_file", etc.
      add :tool_name, :string, null: false
      # The ID from the LLM response (e.g., "toolu_01ABC...")
      add :tool_use_id, :string

      # Input/Output
      # Tool input parameters
      add :input, :map, null: false
      # Tool output (can be large)
      add :output, :text
      add :output_truncated, :boolean, default: false

      # Status: pending, approved, denied, executing, completed, failed, timeout
      add :status, :string, default: "pending", null: false

      # Approval workflow
      add :requires_approval, :boolean, default: false, null: false
      # Link to approval_items if needed
      add :approval_id, :binary_id
      add :approved_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :approved_at, :utc_datetime_usec
      add :denial_reason, :text

      # Execution tracking
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :duration_ms, :integer

      # For file operations - track what changed
      add :file_changes, {:array, :map}, default: []
      # Example: [%{path: "/tmp/foo.py", action: "create", diff: "..."}]

      # For shell commands - capture more detail
      add :exit_code, :integer
      add :stdout, :text
      add :stderr, :text

      # Error tracking
      add :error_type, :string
      add :error_message, :text

      # Sequence within the agent call (multiple tool uses per call)
      add :sequence, :integer, null: false

      # Metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:tool_uses, [:agent_call_id, :sequence])
    create index(:tool_uses, [:session_id])
    create index(:tool_uses, [:tool_name])
    create index(:tool_uses, [:status])
    create index(:tool_uses, [:requires_approval, :status])
    create index(:tool_uses, [:approved_by_id])
  end
end
