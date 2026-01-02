defmodule Command.Indexes.Index do
  @moduledoc """
  Schema for RAG index configurations.

  Indexes define the source, chunking, embedding, and storage
  configuration for vector search.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          slug: String.t() | nil,
          description: String.t() | nil,
          status: String.t(),
          source_type: String.t() | nil,
          source_config: map() | nil,
          chunk_strategy: String.t(),
          chunk_config: map(),
          embedding_provider: String.t(),
          embedding_model: String.t(),
          embedding_dimensions: integer(),
          storage_backend: String.t(),
          storage_config: map(),
          document_count: integer(),
          chunk_count: integer(),
          total_tokens: integer(),
          embedding_cost_cents: integer(),
          last_indexed_at: DateTime.t() | nil,
          indexing_started_at: DateTime.t() | nil,
          indexing_duration_ms: integer() | nil,
          last_error: String.t() | nil,
          auto_reindex: boolean(),
          reindex_schedule: String.t() | nil,
          last_reindex_at: DateTime.t() | nil,
          tracked_commit: String.t() | nil,
          git_config: map(),
          tags: [String.t()],
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @source_types ~w(local_repo github files url)
  @chunk_strategies ~w(fixed semantic code_aware recursive)
  @embedding_providers ~w(openai cohere google local)
  @storage_backends ~w(pgvector weaviate qdrant)

  schema "indexes" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :status, :string, default: "creating"
    field :source_type, :string
    field :source_config, :map
    field :chunk_strategy, :string, default: "semantic"
    field :chunk_config, :map, default: %{}
    field :embedding_provider, :string, default: "openai"
    field :embedding_model, :string, default: "text-embedding-3-small"
    field :embedding_dimensions, :integer, default: 1536
    field :storage_backend, :string, default: "pgvector"
    field :storage_config, :map, default: %{}
    field :document_count, :integer, default: 0
    field :chunk_count, :integer, default: 0
    field :total_tokens, :integer, default: 0
    field :embedding_cost_cents, :integer, default: 0
    field :last_indexed_at, :utc_datetime_usec
    field :indexing_started_at, :utc_datetime_usec
    field :indexing_duration_ms, :integer
    field :last_error, :string
    field :auto_reindex, :boolean, default: false
    field :reindex_schedule, :string
    field :last_reindex_at, :utc_datetime_usec
    field :tracked_commit, :string
    field :git_config, :map, default: %{}
    field :tags, {:array, :string}, default: []
    field :metadata, :map, default: %{}

    belongs_to :user, Command.Accounts.User

    has_many :documents, Command.Indexes.ContextDocument
    has_many :chunks, Command.Indexes.ContextChunk

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new index.
  """
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(index, attrs) do
    index
    |> cast(attrs, [
      :user_id,
      :name,
      :slug,
      :description,
      :source_type,
      :source_config,
      :chunk_strategy,
      :chunk_config,
      :embedding_provider,
      :embedding_model,
      :embedding_dimensions,
      :storage_backend,
      :storage_config,
      :auto_reindex,
      :reindex_schedule,
      :git_config,
      :tags,
      :metadata
    ])
    |> validate_required([:user_id, :name, :slug, :source_type, :source_config])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_length(:slug, min: 1, max: 100)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/)
    |> validate_inclusion(:source_type, @source_types)
    |> validate_inclusion(:chunk_strategy, @chunk_strategies)
    |> validate_inclusion(:embedding_provider, @embedding_providers)
    |> validate_inclusion(:storage_backend, @storage_backends)
    |> validate_number(:embedding_dimensions, greater_than: 0)
    |> unique_constraint([:user_id, :slug])
  end

  @doc """
  Changeset for starting indexing.
  """
  @spec indexing_start_changeset(t() | Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def indexing_start_changeset(index) do
    index
    |> change(%{
      status: "updating",
      indexing_started_at: DateTime.utc_now(),
      last_error: nil
    })
  end

  @doc """
  Changeset for completing indexing successfully.
  """
  @spec indexing_complete_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def indexing_complete_changeset(index, attrs) do
    now = DateTime.utc_now()
    started_at = index.indexing_started_at || now
    duration_ms = DateTime.diff(now, started_at, :millisecond)

    index
    |> cast(attrs, [
      :document_count,
      :chunk_count,
      :total_tokens,
      :embedding_cost_cents,
      :tracked_commit
    ])
    |> put_change(:status, "ready")
    |> put_change(:last_indexed_at, now)
    |> put_change(:indexing_duration_ms, duration_ms)
    |> put_change(:last_error, nil)
  end

  @doc """
  Changeset for recording indexing failure.
  """
  @spec indexing_failure_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def indexing_failure_changeset(index, attrs) do
    now = DateTime.utc_now()
    started_at = index.indexing_started_at || now
    duration_ms = DateTime.diff(now, started_at, :millisecond)

    index
    |> cast(attrs, [:last_error])
    |> put_change(:status, "failed")
    |> put_change(:indexing_duration_ms, duration_ms)
  end

  @doc """
  Changeset for updating index configuration.
  """
  @spec config_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def config_changeset(index, attrs) do
    index
    |> cast(attrs, [
      :chunk_strategy,
      :chunk_config,
      :embedding_provider,
      :embedding_model,
      :embedding_dimensions,
      :auto_reindex,
      :reindex_schedule,
      :git_config,
      :tags,
      :metadata
    ])
    |> validate_inclusion(:chunk_strategy, @chunk_strategies)
    |> validate_inclusion(:embedding_provider, @embedding_providers)
    |> validate_number(:embedding_dimensions, greater_than: 0)
  end
end
