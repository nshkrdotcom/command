defmodule Command.Repo.Migrations.CreateSessions do
  use Ecto.Migration

  def change do
    create table(:sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Identity
      add :name, :string, null: false
      # What is this session for?
      add :purpose, :text
      # URL-friendly identifier
      add :slug, :string

      # Status: active, paused, completed, archived
      add :status, :string, default: "active", null: false

      # Branching support - sessions can fork from other sessions
      add :parent_session_id, references(:sessions, type: :binary_id, on_delete: :nilify_all)
      # Which message was this forked from?
      add :forked_at_message_id, :binary_id

      # Aggregated stats (denormalized for quick access)
      add :message_count, :integer, default: 0, null: false
      add :total_tokens_in, :bigint, default: 0, null: false
      add :total_tokens_out, :bigint, default: 0, null: false
      # Store as cents to avoid float
      add :total_cost_cents, :integer, default: 0, null: false
      add :total_duration_ms, :bigint, default: 0, null: false

      # Context configuration
      # "claude", "codex", "gemini"
      add :default_agent, :string
      # "claude-sonnet-4-20250514", etc.
      add :default_model, :string
      add :system_prompt, :text
      add :temperature, :float
      add :max_tokens, :integer

      # Linked resources
      add :linked_index_ids, {:array, :binary_id}, default: []
      add :linked_workflow_ids, {:array, :binary_id}, default: []

      # Flexible metadata
      add :metadata, :map, default: %{}
      add :tags, {:array, :string}, default: []

      # Git context (if session is tied to a repo/branch)
      add :git_context, :map, default: %{}
      # Example: %{repo: "nsai/snakepit", branch: "main", commit: "abc123"}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:sessions, [:user_id])
    create index(:sessions, [:status])
    create index(:sessions, [:parent_session_id])
    create unique_index(:sessions, [:user_id, :slug], where: "slug IS NOT NULL")
    create index(:sessions, [:tags], using: :gin)
    create index(:sessions, [:updated_at])
  end
end
