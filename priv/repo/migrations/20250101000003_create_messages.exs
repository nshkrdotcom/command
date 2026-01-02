defmodule Command.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :session_id, references(:sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      # Role: user, assistant, system, tool_result
      add :role, :string, null: false

      # Content - can be text or structured (for tool calls, images, etc.)
      add :content, :text
      # For multi-part messages
      add :content_blocks, {:array, :map}, default: []

      # Ordering within session
      add :sequence, :integer, null: false

      # If this is an assistant message, link to the agent call
      # Will be foreign key after agent_calls created
      add :agent_call_id, :binary_id

      # If this is a tool_result, link to the tool use
      # Will be foreign key after tool_uses created
      add :tool_use_id, :binary_id

      # For branching: messages can be "hidden" in a branch
      # Empty = visible in all
      add :visible_in_branches, {:array, :binary_id}, default: []

      # Token counts for this message
      add :token_count, :integer

      # Attachments (file references, images, etc.)
      add :attachments, {:array, :map}, default: []
      # Example: [%{type: "file", path: "/tmp/foo.py", name: "foo.py"}]

      # Metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:messages, [:session_id, :sequence])
    create index(:messages, [:session_id, :role])
    create index(:messages, [:agent_call_id])
    create index(:messages, [:tool_use_id])

    # Full-text search on content
    execute """
              CREATE INDEX messages_content_search_idx ON messages 
              USING gin(to_tsvector('english', coalesce(content, '')))
            """,
            """
              DROP INDEX messages_content_search_idx
            """
  end
end
