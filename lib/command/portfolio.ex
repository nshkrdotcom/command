defmodule Command.Portfolio do
  @moduledoc """
  Integration layer for portfolio_core and portfolio_index.

  This module provides a unified interface for accessing RAG capabilities
  through the portfolio ecosystem. It delegates to registered adapters
  via PortfolioCore's registry.

  ## Usage

      # Get embeddings
      {:ok, embedding} = Command.Portfolio.embed("text to embed")

      # Generate LLM completion
      messages = [%{role: "user", content: "Hello"}]
      {:ok, response} = Command.Portfolio.complete(messages)

      # Retrieve relevant context
      {:ok, chunks} = Command.Portfolio.retrieve("search query")

  ## Required Adapters

  Command requires these adapters to be registered:

  - `:vector_store` - For storing and searching embeddings
  - `:embedder` - For generating embeddings
  - `:llm` - For LLM completions
  - `:retriever` - For RAG retrieval

  Optional adapters:

  - `:chunker` - For text chunking
  - `:reranker` - For result reranking
  """

  require Logger

  @required_adapters [:vector_store, :embedder, :llm, :retriever]

  # ============================================================================
  # Adapter Access
  # ============================================================================

  @doc """
  Get a registered adapter by port name.

  Returns `{adapter_module, config}` tuple.

  ## Examples

      {adapter, config} = Command.Portfolio.adapter!(:embedder)
      adapter.embed("text")
  """
  @spec adapter!(atom()) :: {module(), map() | keyword()}
  def adapter!(port_name) do
    case PortfolioCore.adapter(port_name) do
      nil ->
        raise ArgumentError, "No adapter registered for port: #{port_name}"

      {module, config} ->
        {module, config}
    end
  end

  @doc """
  Get a registered adapter, returning nil if not found.
  """
  @spec adapter(atom()) :: {module(), map() | keyword()} | nil
  def adapter(port_name) do
    PortfolioCore.adapter(port_name)
  end

  @doc """
  Check if all required adapters are registered.
  """
  @spec required_adapters_present?() :: boolean()
  def required_adapters_present? do
    Enum.all?(@required_adapters, fn port ->
      PortfolioCore.adapter(port) != nil
    end)
  end

  @doc """
  Validate that all required adapters are registered and implement
  expected callbacks.

  Raises RuntimeError if validation fails.
  """
  @spec validate_adapters!() :: :ok
  def validate_adapters! do
    Enum.each(@required_adapters, fn port ->
      case PortfolioCore.adapter(port) do
        nil ->
          raise RuntimeError, "Missing required adapter: #{port}"

        {module, _config} ->
          validate_adapter_module!(port, module)
      end
    end)

    :ok
  end

  defp validate_adapter_module!(port, module) do
    # Ensure the module is loaded before checking exports
    _ = Code.ensure_loaded(module)

    required_functions = adapter_required_functions(port)

    for {func, arity} <- required_functions do
      unless function_exported?(module, func, arity) do
        raise RuntimeError,
              "Adapter #{inspect(module)} for #{port} does not implement #{func}/#{arity}"
      end
    end
  end

  # Callbacks without config as first arg
  defp adapter_required_functions(:vector_store), do: [search: 4, store: 4]
  defp adapter_required_functions(:embedder), do: [embed: 2]
  defp adapter_required_functions(:llm), do: [complete: 2]
  defp adapter_required_functions(:retriever), do: [retrieve: 3]
  defp adapter_required_functions(_), do: []

  @doc """
  List all registered ports.
  """
  @spec registered_ports() :: [atom()]
  def registered_ports do
    PortfolioCore.registered_ports()
  end

  # ============================================================================
  # Embedding Operations
  # ============================================================================

  @doc """
  Generate an embedding for text.

  ## Options

  - `:model` - Embedding model to use (default from adapter config)

  ## Examples

      {:ok, embedding} = Command.Portfolio.embed("Hello world")
      # embedding is a list of floats
  """
  @spec embed(String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}
  def embed(text, opts \\ []) do
    {embedder, _config} = adapter!(:embedder)

    case embedder.embed(text, opts) do
      {:ok, %{vector: vector}} -> {:ok, vector}
      {:ok, vector} when is_list(vector) -> {:ok, vector}
      error -> error
    end
  end

  @doc """
  Generate embeddings for multiple texts.
  """
  @spec embed_batch([String.t()], keyword()) :: {:ok, [[float()]]} | {:error, term()}
  def embed_batch(texts, opts \\ []) do
    {embedder, _config} = adapter!(:embedder)

    case embedder.embed_batch(texts, opts) do
      {:ok, %{embeddings: embeddings}} ->
        vectors =
          Enum.map(embeddings, fn
            %{vector: v} -> v
            v when is_list(v) -> v
          end)

        {:ok, vectors}

      {:ok, embeddings} when is_list(embeddings) ->
        {:ok, embeddings}

      error ->
        error
    end
  end

  # ============================================================================
  # LLM Operations
  # ============================================================================

  @doc """
  Generate an LLM completion.

  ## Options

  - `:model` - Model to use (default from adapter config)
  - `:temperature` - Sampling temperature (0.0-1.0)
  - `:max_tokens` - Maximum tokens to generate

  ## Examples

      messages = [%{role: "user", content: "Hello"}]
      {:ok, response} = Command.Portfolio.complete(messages)
      response.content  # "Hello! How can I help you?"
  """
  @spec complete([map()], keyword()) :: {:ok, map()} | {:error, term()}
  def complete(messages, opts \\ []) do
    {llm, _config} = adapter!(:llm)
    llm.complete(messages, opts)
  end

  @doc """
  Stream an LLM completion.

  Returns a stream of delta chunks.
  """
  @spec stream([map()], keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream(messages, opts \\ []) do
    {llm, _config} = adapter!(:llm)
    llm.stream(messages, opts)
  end

  # ============================================================================
  # Retrieval Operations
  # ============================================================================

  @doc """
  Retrieve relevant context for a query.

  ## Options

  - `:k` - Number of results to return (default: 10)
  - `:filters` - Metadata filters to apply

  ## Examples

      {:ok, chunks} = Command.Portfolio.retrieve("How do I deploy?")
      # chunks is a list of %{id, content, score, metadata}
  """
  @spec retrieve(String.t(), map(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def retrieve(query, context \\ %{}, opts \\ []) do
    {retriever, _config} = adapter!(:retriever)

    case retriever.retrieve(query, context, opts) do
      {:ok, %{items: items}} -> {:ok, items}
      {:ok, items} when is_list(items) -> {:ok, items}
      error -> error
    end
  end

  # ============================================================================
  # Chunking Operations
  # ============================================================================

  @doc """
  Chunk text into smaller pieces.

  Requires `:chunker` adapter to be registered.

  ## Options

  - `:chunk_size` - Target chunk size
  - `:chunk_overlap` - Overlap between chunks
  """
  @spec chunk(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def chunk(text, opts \\ []) do
    case adapter(:chunker) do
      nil ->
        {:error, :chunker_not_registered}

      {chunker, config} ->
        # Chunker.chunk/3 takes text, format, and config
        format = Keyword.get(opts, :format, :text)
        chunk_config = Map.new(opts) |> Map.merge(config)
        chunker.chunk(text, format, chunk_config)
    end
  end

  # ============================================================================
  # Reranking Operations
  # ============================================================================

  @doc """
  Rerank results based on query relevance.

  Requires `:reranker` adapter to be registered.
  """
  @spec rerank(String.t(), [map()], keyword()) :: {:ok, [map()]} | {:error, term()}
  def rerank(query, results, opts \\ []) do
    case adapter(:reranker) do
      nil ->
        {:error, :reranker_not_registered}

      {reranker, _config} ->
        reranker.rerank(query, results, opts)
    end
  end

  # ============================================================================
  # Vector Store Operations
  # ============================================================================

  @doc """
  Store an embedding in a vector index.
  """
  @spec store_embedding(String.t(), String.t(), [float()], map()) :: :ok | {:error, term()}
  def store_embedding(index_id, id, embedding, metadata) do
    {store, _config} = adapter!(:vector_store)
    store.store(index_id, id, embedding, metadata)
  end

  @doc """
  Search for similar vectors.
  """
  @spec search_vectors(String.t(), [float()], integer(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def search_vectors(index_id, query_embedding, k, opts \\ []) do
    {store, _config} = adapter!(:vector_store)
    store.search(index_id, query_embedding, k, opts)
  end

  @doc """
  Create a vector index.
  """
  @spec create_index(String.t(), keyword()) :: :ok | {:error, term()}
  def create_index(index_id, opts \\ []) do
    {store, _config} = adapter!(:vector_store)
    config = Map.new(opts)
    store.create_index(index_id, config)
  end

  @doc """
  Delete a vector index.
  """
  @spec delete_index(String.t()) :: :ok | {:error, term()}
  def delete_index(index_id) do
    {store, _config} = adapter!(:vector_store)
    store.delete_index(index_id)
  end

  @doc """
  Get vector index statistics.
  """
  @spec index_stats(String.t()) :: {:ok, map()} | {:error, term()}
  def index_stats(index_id) do
    {store, _config} = adapter!(:vector_store)
    store.index_stats(index_id)
  end
end
