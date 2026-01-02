defmodule Command.Repo.Migrations.CreateApprovalItems do
  use Ecto.Migration

  def change do
    create table(:approval_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :session_id, references(:sessions, type: :binary_id, on_delete: :delete_all)

      # What type of approval is this?
      add :approval_type, :string, null: false
      # Types: "tool_use", "file_write", "shell_command", "workflow_step", "custom"

      # Status: pending, approved, denied, expired, auto_approved
      add :status, :string, default: "pending", null: false

      # Priority: low, normal, high, critical
      add :priority, :string, default: "normal", null: false

      # What is being requested?
      # Human-readable summary
      add :title, :string, null: false
      # Detailed explanation
      add :description, :text
      # The actual data being approved
      add :payload, :map, null: false
      # Example for file_write: 
      # %{path: "/tmp/foo.py", content: "...", action: "create"}
      # Example for shell:
      # %{command: "rm -rf /tmp/test", working_dir: "/home/user"}

      # Source - what generated this approval request?
      # "tool_use", "workflow_step", "manual"
      add :source_type, :string, null: false
      # ID of the source (tool_use_id, workflow_step_id)
      add :source_id, :binary_id

      # Context - additional info for the reviewer
      add :context, :map, default: %{}
      # Could include: agent reasoning, risk assessment, similar past approvals

      # Risk assessment (computed or provided)
      # "low", "medium", "high", "critical"
      add :risk_level, :string
      add :risk_factors, {:array, :string}, default: []
      # Example: ["modifies_system_files", "network_access", "destructive_command"]

      # Decision tracking
      add :decided_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :decided_at, :utc_datetime_usec
      # Why approved/denied
      add :decision_note, :text
      # If reviewer modified before approving
      add :modified_payload, :map

      # Expiration
      add :expires_at, :utc_datetime_usec
      # "deny", "approve", "escalate"
      add :timeout_action, :string, default: "deny"

      # Auto-approval rules (if this matched a rule)
      add :auto_approval_rule_id, :binary_id
      add :auto_approval_reason, :string

      # Notification tracking
      add :notified_at, :utc_datetime_usec
      add :notification_channels, {:array, :string}, default: []

      # Metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:approval_items, [:user_id])
    create index(:approval_items, [:session_id])
    create index(:approval_items, [:status])
    create index(:approval_items, [:approval_type])
    create index(:approval_items, [:priority])
    create index(:approval_items, [:source_type, :source_id])
    create index(:approval_items, [:decided_by_id])
    create index(:approval_items, [:expires_at], where: "status = 'pending'")

    # For pending approvals queue
    create index(:approval_items, [:user_id, :status, :priority, :inserted_at])
  end
end
