defmodule Command.Indexes.ContextChunk do
  @moduledoc """
  Schema for embedded text chunks with vector embeddings.

  Chunks are the atomic units for vector similarity search,
  containing content, embeddings, and positional metadata.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          index_id: Ecto.UUID.t() | nil,
          source_uri: String.t() | nil,
          source_type: String.t() | nil,
          source_metadata: map(),
          content: String.t() | nil,
          content_hash: String.t() | nil,
          chunk_index: integer() | nil,
          start_offset: integer() | nil,
          end_offset: integer() | nil,
          start_line: integer() | nil,
          end_line: integer() | nil,
          token_count: integer() | nil,
          embedding: %Pgvector{} | nil,
          embedding_model: String.t() | nil,
          embedded_at: DateTime.t() | nil,
          language: String.t() | nil,
          code_context: map(),
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @source_types ~w(file url github api)

  schema "context_chunks" do
    field :source_uri, :string
    field :source_type, :string
    field :source_metadata, :map, default: %{}
    field :content, :string
    field :content_hash, :string
    field :chunk_index, :integer
    field :start_offset, :integer
    field :end_offset, :integer
    field :start_line, :integer
    field :end_line, :integer
    field :token_count, :integer
    field :embedding, Pgvector.Ecto.Vector
    field :embedding_model, :string
    field :embedded_at, :utc_datetime_usec
    field :language, :string
    field :code_context, :map, default: %{}
    field :metadata, :map, default: %{}

    belongs_to :index, Command.Indexes.Index

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new context chunk.
  """
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(chunk, attrs) do
    chunk
    |> cast(attrs, [
      :index_id,
      :source_uri,
      :source_type,
      :source_metadata,
      :content,
      :content_hash,
      :chunk_index,
      :start_offset,
      :end_offset,
      :start_line,
      :end_line,
      :token_count,
      :language,
      :code_context,
      :metadata
    ])
    |> validate_required([
      :index_id,
      :source_uri,
      :source_type,
      :content,
      :content_hash,
      :chunk_index,
      :token_count
    ])
    |> validate_inclusion(:source_type, @source_types)
    |> validate_number(:chunk_index, greater_than_or_equal_to: 0)
    |> validate_number(:token_count, greater_than: 0)
    |> unique_constraint([:index_id, :content_hash])
    |> foreign_key_constraint(:index_id)
  end

  @doc """
  Changeset for adding embedding to a chunk.
  """
  @spec embedding_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def embedding_changeset(chunk, attrs) do
    chunk
    |> cast(attrs, [:embedding, :embedding_model])
    |> put_change(:embedded_at, DateTime.utc_now())
  end

  @doc """
  Changeset for updating chunk metadata.
  """
  @spec update_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def update_changeset(chunk, attrs) do
    chunk
    |> cast(attrs, [:language, :code_context, :metadata])
  end
end
