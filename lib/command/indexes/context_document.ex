defmodule Command.Indexes.ContextDocument do
  @moduledoc """
  Schema for source documents within an index.

  Represents full documents before chunking, tracking content hashes
  for change detection and processing state.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          index_id: Ecto.UUID.t() | nil,
          uri: String.t() | nil,
          title: String.t() | nil,
          source_type: String.t() | nil,
          content_hash: String.t() | nil,
          size_bytes: integer() | nil,
          mime_type: String.t() | nil,
          language: String.t() | nil,
          encoding: String.t() | nil,
          git_commit: String.t() | nil,
          git_branch: String.t() | nil,
          chunked_at: DateTime.t() | nil,
          chunk_count: integer(),
          total_tokens: integer(),
          processing_error: String.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @source_types ~w(file url github api)

  schema "context_documents" do
    field :uri, :string
    field :title, :string
    field :source_type, :string
    field :content_hash, :string
    field :size_bytes, :integer
    field :mime_type, :string
    field :language, :string
    field :encoding, :string
    field :git_commit, :string
    field :git_branch, :string
    field :chunked_at, :utc_datetime_usec
    field :chunk_count, :integer, default: 0
    field :total_tokens, :integer, default: 0
    field :processing_error, :string
    field :metadata, :map, default: %{}

    belongs_to :index, Command.Indexes.Index

    has_many :chunks, Command.Indexes.ContextChunk,
      foreign_key: :index_id,
      references: :index_id,
      where: [source_uri: {:fragment, "context_documents.uri"}]

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new context document.
  """
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(document, attrs) do
    document
    |> cast(attrs, [
      :index_id,
      :uri,
      :title,
      :source_type,
      :content_hash,
      :size_bytes,
      :mime_type,
      :language,
      :encoding,
      :git_commit,
      :git_branch,
      :metadata
    ])
    |> validate_required([:index_id, :uri, :source_type, :content_hash])
    |> validate_inclusion(:source_type, @source_types)
    |> unique_constraint([:index_id, :uri])
    |> foreign_key_constraint(:index_id)
  end

  @doc """
  Changeset for recording successful chunking.
  """
  @spec chunking_complete_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def chunking_complete_changeset(document, attrs) do
    document
    |> cast(attrs, [:chunk_count, :total_tokens])
    |> put_change(:chunked_at, DateTime.utc_now())
    |> put_change(:processing_error, nil)
  end

  @doc """
  Changeset for recording chunking failure.
  """
  @spec chunking_failure_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def chunking_failure_changeset(document, attrs) do
    document
    |> cast(attrs, [:processing_error])
  end

  @doc """
  Changeset for updating document metadata.
  """
  @spec update_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def update_changeset(document, attrs) do
    document
    |> cast(attrs, [
      :title,
      :content_hash,
      :size_bytes,
      :mime_type,
      :language,
      :git_commit,
      :git_branch,
      :metadata
    ])
  end
end
