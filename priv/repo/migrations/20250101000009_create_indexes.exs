defmodule Command.Repo.Migrations.CreateIndexes do
  use Ecto.Migration

  def change do
    create table(:indexes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Identity
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text

      # Status: creating, ready, updating, failed, archived
      add :status, :string, default: "creating", null: false

      # Source configuration - where does the data come from?
      # "local_repo", "github", "files", "url"
      add :source_type, :string, null: false
      add :source_config, :map, null: false
      # Examples:
      # local_repo: %{path: "/home/user/project", include: ["**/*.ex"], exclude: ["deps/**"]}
      # github: %{repo: "owner/repo", branch: "main", token_ref: "github_token"}
      # files: %{paths: ["/path/to/file1", "/path/to/file2"]}
      # url: %{urls: ["https://docs.example.com"], crawl_depth: 2}

      # Chunking configuration
      # "fixed", "semantic", "code_aware"
      add :chunk_strategy, :string, default: "semantic"
      add :chunk_config, :map, default: %{}
      # Example: %{max_tokens: 512, overlap_tokens: 50}

      # Embedding configuration
      # "openai", "cohere", "local"
      add :embedding_provider, :string, default: "openai"
      add :embedding_model, :string, default: "text-embedding-3-small"
      add :embedding_dimensions, :integer, default: 1536

      # Storage backend - where are embeddings stored?
      # "pgvector", "weaviate", "qdrant"
      add :storage_backend, :string, default: "pgvector"
      add :storage_config, :map, default: %{}
      # Example for weaviate: %{class_name: "MyIndex", url: "http://localhost:8080"}

      # Stats
      add :document_count, :integer, default: 0
      add :chunk_count, :integer, default: 0
      add :total_tokens, :bigint, default: 0
      add :embedding_cost_cents, :integer, default: 0

      # Indexing state
      add :last_indexed_at, :utc_datetime_usec
      add :indexing_started_at, :utc_datetime_usec
      add :indexing_duration_ms, :bigint
      add :last_error, :text

      # Schedule for re-indexing
      add :auto_reindex, :boolean, default: false
      # Cron expression
      add :reindex_schedule, :string
      add :last_reindex_at, :utc_datetime_usec

      # Git tracking (for repo-based indexes)
      # Last indexed commit SHA
      add :tracked_commit, :string
      add :git_config, :map, default: %{}

      # Tags and categorization
      add :tags, {:array, :string}, default: []

      # Metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:indexes, [:user_id])
    create index(:indexes, [:status])
    create unique_index(:indexes, [:user_id, :slug])
    create index(:indexes, [:source_type])
    create index(:indexes, [:storage_backend])
    create index(:indexes, [:tags], using: :gin)
  end
end
