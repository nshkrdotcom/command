defmodule Command.Repo.Migrations.CreateApprovalRules do
  use Ecto.Migration

  def change do
    create table(:approval_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Identity
      add :name, :string, null: false
      add :description, :text

      # Status: active, disabled
      add :status, :string, default: "active", null: false

      # What does this rule apply to?
      # "tool_use", "file_write", "shell_command", "*"
      add :approval_type, :string, null: false
      # Empty = all tools of this type
      add :tool_names, {:array, :string}, default: []

      # Conditions - when does this rule match?
      add :conditions, :map, null: false
      # Examples:
      # %{path_pattern: "/tmp/**", action: "create"}  -- auto-approve temp file creates
      # %{command_pattern: "mix test*"}               -- auto-approve mix test commands
      # %{risk_level: ["low"]}                        -- auto-approve low-risk items

      # Action when matched
      # "approve", "deny", "require_review"
      add :action, :string, null: false
      # Note to attach to auto-decisions
      add :action_note, :string

      # Limits
      add :max_auto_approvals_per_hour, :integer
      add :max_auto_approvals_per_session, :integer
      add :current_hour_count, :integer, default: 0
      add :hour_reset_at, :utc_datetime_usec

      # Priority (higher = checked first)
      add :priority, :integer, default: 0

      # Audit
      add :times_triggered, :integer, default: 0
      add :last_triggered_at, :utc_datetime_usec

      # Scope
      # Empty = all sessions
      add :applies_to_sessions, {:array, :binary_id}, default: []
      # Empty = all workflows
      add :applies_to_workflows, {:array, :binary_id}, default: []

      # Metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:approval_rules, [:user_id])
    create index(:approval_rules, [:status])
    create index(:approval_rules, [:approval_type])
    create index(:approval_rules, [:user_id, :status, :priority])
  end
end
