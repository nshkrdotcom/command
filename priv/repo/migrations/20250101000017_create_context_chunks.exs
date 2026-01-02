defmodule Command.Repo.Migrations.CreateContextChunks do
  use Ecto.Migration

  def change do
    # Enable pgvector extension
    execute "CREATE EXTENSION IF NOT EXISTS vector", "DROP EXTENSION IF EXISTS vector"

    create table(:context_chunks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :index_id, references(:indexes, type: :binary_id, on_delete: :delete_all), null: false

      # Source document info
      # File path, URL, or unique identifier
      add :source_uri, :string, null: false
      # "file", "url", "github", "api"
      add :source_type, :string, null: false
      add :source_metadata, :map, default: %{}
      # Example: %{repo: "org/repo", path: "lib/foo.ex", commit: "abc123"}

      # Chunk content
      add :content, :text, null: false
      # For deduplication
      add :content_hash, :string, null: false

      # Position within source
      # Order within the document
      add :chunk_index, :integer, null: false
      # Character offset in original
      add :start_offset, :integer
      add :end_offset, :integer
      add :start_line, :integer
      add :end_line, :integer

      # Token info
      add :token_count, :integer, null: false

      # Embedding (pgvector)
      # Using 1536 dimensions (OpenAI default), but this should be configurable
      add :embedding, :vector, size: 1536

      # Embedding metadata
      add :embedding_model, :string
      add :embedded_at, :utc_datetime_usec

      # For code chunks - additional context
      add :language, :string
      add :code_context, :map, default: %{}
      # Example: %{module: "MyApp.Foo", function: "bar/2", type: "function_def"}

      # Chunk metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:context_chunks, [:index_id])
    create index(:context_chunks, [:source_uri])
    create unique_index(:context_chunks, [:index_id, :content_hash])
    create index(:context_chunks, [:language])

    # HNSW index for fast similarity search
    execute """
              CREATE INDEX context_chunks_embedding_idx ON context_chunks 
              USING hnsw (embedding vector_cosine_ops)
              WITH (m = 16, ef_construction = 64)
            """,
            """
              DROP INDEX context_chunks_embedding_idx
            """

    # Documents table - represents full source documents
    create table(:context_documents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :index_id, references(:indexes, type: :binary_id, on_delete: :delete_all), null: false

      # Identity
      add :uri, :string, null: false
      add :title, :string
      add :source_type, :string, null: false

      # Content hash for change detection
      add :content_hash, :string, null: false
      add :size_bytes, :bigint

      # Metadata
      add :mime_type, :string
      add :language, :string
      add :encoding, :string

      # Git info (if applicable)
      add :git_commit, :string
      add :git_branch, :string

      # Processing state
      add :chunked_at, :utc_datetime_usec
      add :chunk_count, :integer, default: 0
      add :total_tokens, :integer, default: 0
      add :processing_error, :text

      # Metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:context_documents, [:index_id])
    create unique_index(:context_documents, [:index_id, :uri])
    create index(:context_documents, [:content_hash])
  end
end
