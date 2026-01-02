defmodule Command.Repo.Migrations.CreatePresenceRecords do
  use Ecto.Migration

  def change do
    # Presence records for tracking who's viewing/editing what
    # This complements Phoenix.Presence with persistence
    create table(:presence_records, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # What are they present in?
      # "session", "workflow_run", "approval_item"
      add :resource_type, :string, null: false
      add :resource_id, :binary_id, null: false

      # Presence state
      # "viewing", "editing", "idle", "away"
      add :status, :string, default: "viewing"

      # Client info
      # Unique per browser tab
      add :client_id, :string, null: false
      # "desktop", "mobile", "tablet"
      add :device_type, :string
      add :user_agent, :string

      # Cursor/selection state (for collaborative features)
      add :cursor_state, :map, default: %{}
      # Example: %{line: 42, column: 10, selection: %{start: ..., end: ...}}

      # Activity tracking
      add :joined_at, :utc_datetime_usec, null: false
      add :last_seen_at, :utc_datetime_usec, null: false
      add :left_at, :utc_datetime_usec

      # Metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:presence_records, [:user_id])
    create index(:presence_records, [:resource_type, :resource_id])
    create unique_index(:presence_records, [:client_id])
    create index(:presence_records, [:last_seen_at])

    # Activity log for audit trail
    create table(:activity_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      # What happened
      add :action, :string, null: false
      # Actions: "session.create", "session.update", "agent.call", "tool.approve", etc.

      # What resource was affected
      add :resource_type, :string, null: false
      add :resource_id, :binary_id, null: false

      # Details
      add :details, :map, default: %{}
      # Example for tool.approve: %{tool_name: "bash", approved: true}

      # Context
      add :session_id, :binary_id
      add :client_id, :string
      add :ip_address, :string

      # Timing
      add :occurred_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:activity_logs, [:user_id])
    create index(:activity_logs, [:resource_type, :resource_id])
    create index(:activity_logs, [:action])
    create index(:activity_logs, [:session_id])
    create index(:activity_logs, [:occurred_at])

    # Partition hint: activity_logs could be partitioned by month in production
  end
end
