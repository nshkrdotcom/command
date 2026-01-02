defmodule Command.Repo.Migrations.CreateArtifacts do
  use Ecto.Migration

  def change do
    create table(:artifacts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :session_id, references(:sessions, type: :binary_id, on_delete: :nilify_all)

      # Identity
      add :name, :string, null: false
      add :description, :text

      # Type: file, code, diff, image, document, archive, other
      add :artifact_type, :string, null: false
      add :mime_type, :string

      # Storage
      # "local", "s3", "inline"
      add :storage_backend, :string, null: false
      # Path for local/s3
      add :storage_path, :string
      # Key for s3
      add :storage_key, :string
      # For small artifacts stored directly
      add :inline_content, :binary

      # File metadata
      add :size_bytes, :bigint
      # SHA256
      add :checksum, :string
      add :original_filename, :string

      # For code artifacts
      add :language, :string
      add :line_count, :integer

      # Source - what created this artifact?
      # "agent_output", "tool_result", "upload", "workflow"
      add :source_type, :string
      add :source_id, :binary_id

      # Versioning (artifacts can be versioned)
      add :version, :integer, default: 1
      add :previous_version_id, references(:artifacts, type: :binary_id, on_delete: :nilify_all)
      add :is_latest, :boolean, default: true

      # Git linkage
      add :git_commit, :string
      add :git_repo, :string
      add :git_path, :string

      # Diff-specific fields
      add :diff_base_artifact_id, references(:artifacts, type: :binary_id, on_delete: :nilify_all)
      add :diff_content, :text
      add :additions, :integer
      add :deletions, :integer

      # Access control
      # "private", "shared", "public"
      add :visibility, :string, default: "private"
      add :shared_with_user_ids, {:array, :binary_id}, default: []

      # Retention
      add :expires_at, :utc_datetime_usec
      # "permanent", "session", "temporary"
      add :retention_policy, :string

      # Tags and categorization
      add :tags, {:array, :string}, default: []

      # Metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:artifacts, [:user_id])
    create index(:artifacts, [:session_id])
    create index(:artifacts, [:artifact_type])
    create index(:artifacts, [:source_type, :source_id])
    create index(:artifacts, [:previous_version_id])
    create index(:artifacts, [:tags], using: :gin)
    create index(:artifacts, [:expires_at], where: "expires_at IS NOT NULL")
    create index(:artifacts, [:checksum])
  end
end
