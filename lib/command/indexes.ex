defmodule Command.Indexes do
  @moduledoc """
  The Indexes context.

  Manages RAG indexes and vector search.
  """

  import Ecto.Query

  alias Command.Accounts.User
  alias Command.Indexes.{ContextChunk, ContextDocument, Index}
  alias Command.Repo

  # Indexes

  @doc """
  Creates an index.
  """
  @spec create_index(User.t(), map()) :: {:ok, Index.t()} | {:error, Ecto.Changeset.t()}
  def create_index(user, attrs) do
    attrs = Map.put(attrs, :user_id, user.id)

    %Index{}
    |> Index.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets an index by ID.
  """
  @spec get_index(Ecto.UUID.t()) :: Index.t() | nil
  def get_index(id), do: Repo.get(Index, id)

  @doc """
  Gets an index by slug for a user.
  """
  @spec get_index_by_slug(User.t(), String.t()) :: Index.t() | nil
  def get_index_by_slug(user, slug) do
    Repo.get_by(Index, user_id: user.id, slug: slug)
  end

  @doc """
  Lists indexes for a user.
  """
  @spec list_indexes(User.t(), keyword()) :: [Index.t()]
  def list_indexes(user, opts \\ []) do
    Index
    |> where([i], i.user_id == ^user.id)
    |> apply_index_filters(opts)
    |> order_by([i], desc: i.updated_at)
    |> Repo.all()
  end

  @doc """
  Starts indexing.
  """
  @spec start_indexing(Index.t()) :: {:ok, Index.t()} | {:error, Ecto.Changeset.t()}
  def start_indexing(index) do
    index
    |> Index.indexing_start_changeset()
    |> Repo.update()
  end

  @doc """
  Completes indexing.
  """
  @spec complete_indexing(Index.t(), map()) :: {:ok, Index.t()} | {:error, Ecto.Changeset.t()}
  def complete_indexing(index, attrs) do
    index
    |> Index.indexing_complete_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Fails indexing.
  """
  @spec fail_indexing(Index.t(), String.t()) :: {:ok, Index.t()} | {:error, Ecto.Changeset.t()}
  def fail_indexing(index, error) do
    index
    |> Index.indexing_failure_changeset(%{last_error: error})
    |> Repo.update()
  end

  # Context Documents

  @doc """
  Creates or updates a context document.
  """
  @spec upsert_document(Index.t(), map()) ::
          {:ok, ContextDocument.t()} | {:error, Ecto.Changeset.t()}
  def upsert_document(index, attrs) do
    attrs = Map.put(attrs, :index_id, index.id)

    case Repo.get_by(ContextDocument, index_id: index.id, uri: attrs[:uri]) do
      nil ->
        %ContextDocument{}
        |> ContextDocument.create_changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> ContextDocument.update_changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Lists documents in an index.
  """
  @spec list_documents(Index.t(), keyword()) :: [ContextDocument.t()]
  def list_documents(index, opts \\ []) do
    ContextDocument
    |> where([d], d.index_id == ^index.id)
    |> apply_document_filters(opts)
    |> order_by([d], asc: d.uri)
    |> Repo.all()
  end

  # Context Chunks

  @doc """
  Creates a context chunk.
  """
  @spec create_chunk(Index.t(), map()) :: {:ok, ContextChunk.t()} | {:error, Ecto.Changeset.t()}
  def create_chunk(index, attrs) do
    attrs = Map.put(attrs, :index_id, index.id)

    %ContextChunk{}
    |> ContextChunk.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Adds embedding to a chunk.
  """
  @spec add_chunk_embedding(ContextChunk.t(), map()) ::
          {:ok, ContextChunk.t()} | {:error, Ecto.Changeset.t()}
  def add_chunk_embedding(chunk, attrs) do
    chunk
    |> ContextChunk.embedding_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists chunks for an index.
  """
  @spec list_chunks(Index.t(), keyword()) :: [ContextChunk.t()]
  def list_chunks(index, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    ContextChunk
    |> where([c], c.index_id == ^index.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Searches chunks by vector similarity.

  Note: This is a simplified implementation. In production,
  use portfolio_index's Pgvector adapter for proper vector search.
  """
  @spec search_chunks(Index.t(), [float()], keyword()) :: [ContextChunk.t()]
  def search_chunks(index, embedding, opts \\ []) do
    k = Keyword.get(opts, :k, 10)

    ContextChunk
    |> where([c], c.index_id == ^index.id)
    |> where([c], not is_nil(c.embedding))
    |> order_by([c], fragment("embedding <=> ?", ^embedding))
    |> limit(^k)
    |> Repo.all()
  end

  @doc """
  Deletes all chunks for a source URI.
  """
  @spec delete_chunks_for_source(Index.t(), String.t()) :: {integer(), nil}
  def delete_chunks_for_source(index, source_uri) do
    ContextChunk
    |> where([c], c.index_id == ^index.id and c.source_uri == ^source_uri)
    |> Repo.delete_all()
  end

  @doc """
  Gets index statistics.
  """
  @spec get_index_stats(Index.t()) :: map()
  def get_index_stats(index) do
    document_count =
      ContextDocument
      |> where([d], d.index_id == ^index.id)
      |> Repo.aggregate(:count)

    chunk_count =
      ContextChunk
      |> where([c], c.index_id == ^index.id)
      |> Repo.aggregate(:count)

    embedded_count =
      ContextChunk
      |> where([c], c.index_id == ^index.id and not is_nil(c.embedding))
      |> Repo.aggregate(:count)

    total_tokens =
      ContextChunk
      |> where([c], c.index_id == ^index.id)
      |> Repo.aggregate(:sum, :token_count) || 0

    %{
      document_count: document_count,
      chunk_count: chunk_count,
      embedded_count: embedded_count,
      total_tokens: total_tokens,
      embedding_coverage: if(chunk_count > 0, do: embedded_count / chunk_count * 100, else: 0)
    }
  end

  # Private helpers

  defp apply_index_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:status, status}, query ->
        where(query, [i], i.status == ^status)

      {:source_type, source_type}, query ->
        where(query, [i], i.source_type == ^source_type)

      {:limit, limit}, query ->
        limit(query, ^limit)

      _, query ->
        query
    end)
  end

  defp apply_document_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:language, language}, query ->
        where(query, [d], d.language == ^language)

      {:limit, limit}, query ->
        limit(query, ^limit)

      _, query ->
        query
    end)
  end
end
