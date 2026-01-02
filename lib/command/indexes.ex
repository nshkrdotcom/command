defmodule Command.Indexes do
  @moduledoc """
  The Indexes context.

  Manages RAG indexes and vector search by delegating to portfolio_core/portfolio_index
  for actual RAG operations while maintaining Command-level metadata tracking.

  ## Architecture

  Command.Indexes serves two purposes:

  1. **Metadata Tracking** - Maintains Ecto schemas for tracking index state,
     documents indexed, and indexing progress. This is Command's domain.

  2. **Portfolio Delegation** - Delegates actual vector operations (embedding,
     search, storage) to portfolio_index adapters via portfolio_core registry.

  ## Usage

      # Search using portfolio's hybrid retrieval
      {:ok, results} = Command.Indexes.search("my_index", "search query", k: 10)

      # Embed text using portfolio's embedder
      {:ok, embedding} = Command.Indexes.embed_text("text to embed")

      # Chunk text using portfolio's chunker
      {:ok, chunks} = Command.Indexes.chunk_text("long text to chunk")
  """

  import Ecto.Query

  alias Command.Accounts.User
  alias Command.Indexes.{ContextChunk, ContextDocument, Index}
  alias Command.Portfolio
  alias Command.Repo

  # ============================================================================
  # Portfolio-Delegated Operations (NEW - for RAG)
  # ============================================================================

  @doc """
  Search an index using portfolio's retrieval adapter.

  This is the primary search interface that uses portfolio_index's
  hybrid retrieval (vector + fulltext with RRF fusion).

  ## Options

  - `:k` - Number of results (default: 10)
  - `:filters` - Metadata filters

  ## Examples

      {:ok, results} = Command.Indexes.search("my_codebase", "how to authenticate")
  """
  @spec search(String.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def search(index_id, query, opts \\ []) do
    context = %{index_id: index_id}
    Portfolio.retrieve(query, context, opts)
  end

  @doc """
  Embed text and search using portfolio adapters.

  Generates an embedding for the query and searches the vector store directly.
  Use `search/3` for hybrid retrieval instead.
  """
  @spec embed_and_search(String.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def embed_and_search(index_id, query, opts \\ []) do
    k = Keyword.get(opts, :k, 10)

    with {:ok, embedding} <- Portfolio.embed(query) do
      Portfolio.search_vectors(index_id, embedding, k, opts)
    end
  end

  @doc """
  Embed text using portfolio's embedder.
  """
  @spec embed_text(String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}
  def embed_text(text, opts \\ []) do
    Portfolio.embed(text, opts)
  end

  @doc """
  Chunk text using portfolio's chunker.

  ## Options

  - `:chunk_size` - Target chunk size (default: from adapter config)
  - `:chunk_overlap` - Overlap between chunks (default: from adapter config)
  """
  @spec chunk_text(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def chunk_text(text, opts \\ []) do
    Portfolio.chunk(text, opts)
  end

  @doc """
  Store an embedding in the portfolio vector store.
  """
  @spec store_embedding(String.t(), String.t(), [float()], map()) :: :ok | {:error, term()}
  def store_embedding(index_id, chunk_id, embedding, metadata) do
    Portfolio.store_embedding(index_id, chunk_id, embedding, metadata)
  end

  @doc """
  Create a vector index in portfolio's vector store.

  ## Options

  - `:dimensions` - Vector dimensions (required)
  - `:metric` - Distance metric (:cosine, :euclidean, :dot_product)
  """
  @spec create_index(String.t(), keyword()) :: :ok | {:error, term()}
  def create_index(index_id, opts) do
    Portfolio.create_index(index_id, opts)
  end

  @doc """
  Delete a vector index from portfolio's vector store.
  """
  @spec delete_index(String.t()) :: :ok | {:error, term()}
  def delete_index(index_id) do
    Portfolio.delete_index(index_id)
  end

  @doc """
  Get vector index statistics from portfolio's vector store.
  """
  @spec index_stats(String.t()) :: {:ok, map()} | {:error, term()}
  def index_stats(index_id) do
    Portfolio.index_stats(index_id)
  end

  # ============================================================================
  # Index Metadata Management (Command's domain)
  # ============================================================================

  @doc """
  Creates an index metadata record.

  This creates tracking metadata in Command's database. Use `create_index/2`
  to create the actual vector index in the portfolio vector store.
  """
  @spec create_index_record(User.t(), map()) :: {:ok, Index.t()} | {:error, Ecto.Changeset.t()}
  def create_index_record(user, attrs) do
    attrs = Map.put(attrs, :user_id, user.id)

    %Index{}
    |> Index.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns a changeset for tracking index changes.

  ## Examples

      iex> change_index(index)
      %Ecto.Changeset{data: %Index{}}

      iex> change_index(index, %{name: "New Name"})
      %Ecto.Changeset{data: %Index{}}
  """
  @spec change_index(Index.t(), map()) :: Ecto.Changeset.t()
  def change_index(%Index{} = index, attrs \\ %{}) do
    Index.create_changeset(index, attrs)
  end

  @doc """
  Gets an index metadata record by ID.
  """
  @spec get_index_record(Ecto.UUID.t()) :: Index.t() | nil
  def get_index_record(id), do: Repo.get(Index, id)

  @doc """
  Gets an index metadata record by slug for a user.
  """
  @spec get_index_record_by_slug(User.t(), String.t()) :: Index.t() | nil
  def get_index_record_by_slug(user, slug) do
    Repo.get_by(Index, user_id: user.id, slug: slug)
  end

  @doc """
  Lists index metadata records for a user.
  """
  @spec list_index_records(User.t(), keyword()) :: [Index.t()]
  def list_index_records(user, opts \\ []) do
    Index
    |> where([i], i.user_id == ^user.id)
    |> apply_index_filters(opts)
    |> order_by([i], desc: i.updated_at)
    |> Repo.all()
  end

  @doc """
  Starts indexing - updates metadata status.
  """
  @spec start_indexing(Index.t()) :: {:ok, Index.t()} | {:error, Ecto.Changeset.t()}
  def start_indexing(index) do
    index
    |> Index.indexing_start_changeset()
    |> Repo.update()
    |> broadcast_index_change(:indexing_started)
  end

  @doc """
  Completes indexing - updates metadata status.
  """
  @spec complete_indexing(Index.t(), map()) :: {:ok, Index.t()} | {:error, Ecto.Changeset.t()}
  def complete_indexing(index, attrs) do
    index
    |> Index.indexing_complete_changeset(attrs)
    |> Repo.update()
    |> broadcast_index_change(:indexing_completed)
  end

  @doc """
  Fails indexing - updates metadata status.
  """
  @spec fail_indexing(Index.t(), String.t()) :: {:ok, Index.t()} | {:error, Ecto.Changeset.t()}
  def fail_indexing(index, error) do
    index
    |> Index.indexing_failure_changeset(%{last_error: error})
    |> Repo.update()
    |> broadcast_index_change(:indexing_failed)
  end

  # ============================================================================
  # Document Metadata Management
  # ============================================================================

  @doc """
  Creates or updates a context document metadata record.
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
  Returns a changeset for tracking document changes.

  ## Examples

      iex> change_document(document)
      %Ecto.Changeset{data: %ContextDocument{}}

      iex> change_document(document, %{title: "Updated Title"})
      %Ecto.Changeset{data: %ContextDocument{}}
  """
  @spec change_document(ContextDocument.t(), map()) :: Ecto.Changeset.t()
  def change_document(%ContextDocument{} = document, attrs \\ %{}) do
    ContextDocument.create_changeset(document, attrs)
  end

  @doc """
  Lists document metadata records in an index.
  """
  @spec list_documents(Index.t(), keyword()) :: [ContextDocument.t()]
  def list_documents(index, opts \\ []) do
    ContextDocument
    |> where([d], d.index_id == ^index.id)
    |> apply_document_filters(opts)
    |> order_by([d], asc: d.uri)
    |> Repo.all()
  end

  # ============================================================================
  # Chunk Metadata Management (DEPRECATED - use portfolio for embeddings)
  # ============================================================================

  @doc """
  Creates a context chunk metadata record.

  Note: For storing embeddings, use `store_embedding/4` which delegates
  to portfolio's vector store.
  """
  @spec create_chunk(Index.t(), map()) :: {:ok, ContextChunk.t()} | {:error, Ecto.Changeset.t()}
  def create_chunk(index, attrs) do
    attrs = Map.put(attrs, :index_id, index.id)

    %ContextChunk{}
    |> ContextChunk.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns a changeset for tracking chunk changes.

  ## Examples

      iex> change_chunk(chunk)
      %Ecto.Changeset{data: %ContextChunk{}}

      iex> change_chunk(chunk, %{language: "elixir"})
      %Ecto.Changeset{data: %ContextChunk{}}
  """
  @spec change_chunk(ContextChunk.t(), map()) :: Ecto.Changeset.t()
  def change_chunk(%ContextChunk{} = chunk, attrs \\ %{}) do
    ContextChunk.create_changeset(chunk, attrs)
  end

  @doc """
  Adds embedding to a chunk metadata record.

  DEPRECATED: Use `store_embedding/4` to store in portfolio's vector store.
  """
  @spec add_chunk_embedding(ContextChunk.t(), map()) ::
          {:ok, ContextChunk.t()} | {:error, Ecto.Changeset.t()}
  def add_chunk_embedding(chunk, attrs) do
    chunk
    |> ContextChunk.embedding_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists chunk metadata records for an index.
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

  DEPRECATED: Use `search/3` for portfolio-backed retrieval.
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
  Deletes all chunk metadata records for a source URI.
  """
  @spec delete_chunks_for_source(Index.t(), String.t()) :: {integer(), nil}
  def delete_chunks_for_source(index, source_uri) do
    ContextChunk
    |> where([c], c.index_id == ^index.id and c.source_uri == ^source_uri)
    |> Repo.delete_all()
  end

  @doc """
  Gets index metadata statistics.

  For vector store statistics, use `index_stats/1`.
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

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp broadcast_index_change(result, event) do
    case result do
      {:ok, index} = success ->
        _ = Command.PubSub.broadcast("index:#{index.id}", event, index)
        _ = Command.PubSub.broadcast("user:#{index.user_id}:indexes", event, index)
        success

      error ->
        error
    end
  end

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
