defmodule Command.Test.PortfolioMocks do
  @moduledoc """
  Mock adapters for testing portfolio integration.

  These mocks implement the PortfolioCore port behaviors for unit testing
  without hitting real APIs or databases.
  """

  defmodule MockVectorStore do
    @moduledoc "Mock VectorStore adapter for tests"
    @behaviour PortfolioCore.Ports.VectorStore

    @impl true
    def create_index(_index_id, _config), do: :ok

    @impl true
    def delete_index(_index_id), do: :ok

    @impl true
    def store(_index_id, _id, _embedding, _metadata), do: :ok

    @impl true
    def store_batch(_index_id, _items), do: {:ok, 0}

    @impl true
    def search(_index_id, _query_embedding, _k, _opts) do
      {:ok,
       [
         %{id: "chunk_1", score: 0.95, metadata: %{"content" => "Test content 1"}, vector: nil},
         %{id: "chunk_2", score: 0.85, metadata: %{"content" => "Test content 2"}, vector: nil}
       ]}
    end

    @impl true
    def delete(_index_id, _id), do: :ok

    @impl true
    def index_stats(_index_id) do
      {:ok, %{count: 100, dimensions: 1536, metric: :cosine, size_bytes: nil}}
    end
  end

  defmodule MockEmbedder do
    @moduledoc "Mock Embedder adapter for tests"
    @behaviour PortfolioCore.Ports.Embedder

    @impl true
    def embed(_text, _opts) do
      # Return a fake 1536-dimensional embedding result
      {:ok,
       %{
         vector: List.duplicate(0.1, 1536),
         model: "text-embedding-3-small",
         dimensions: 1536,
         token_count: 10
       }}
    end

    @impl true
    def embed_batch(texts, _opts) do
      embeddings =
        Enum.map(texts, fn _ ->
          %{
            vector: List.duplicate(0.1, 1536),
            model: "text-embedding-3-small",
            dimensions: 1536,
            token_count: 10
          }
        end)

      {:ok, %{embeddings: embeddings, total_tokens: length(texts) * 10}}
    end

    @impl true
    def dimensions(_model), do: 1536

    @impl true
    def supported_models, do: ["text-embedding-3-small", "text-embedding-3-large"]
  end

  defmodule MockLLM do
    @moduledoc "Mock LLM adapter for tests"
    @behaviour PortfolioCore.Ports.LLM

    @impl true
    def complete(_messages, _opts) do
      {:ok,
       %{
         content: "This is a mock LLM response.",
         model: "mock-model",
         usage: %{
           input_tokens: 10,
           output_tokens: 20
         },
         finish_reason: :stop
       }}
    end

    @impl true
    def stream(_messages, _opts) do
      {:ok,
       Stream.map(["This ", "is ", "streaming."], fn chunk ->
         %{delta: chunk, finish_reason: nil}
       end)}
    end

    @impl true
    def supported_models do
      ["mock-model", "mock-model-large"]
    end

    @impl true
    def model_info(_model) do
      %{
        context_window: 128_000,
        max_output: 4096,
        supports_tools: true
      }
    end
  end

  defmodule MockRetriever do
    @moduledoc "Mock Retriever adapter for tests"
    @behaviour PortfolioCore.Ports.Retriever

    @impl true
    def retrieve(query, _context, _opts) do
      {:ok,
       %{
         items: [
           %{
             id: "chunk_1",
             content: "This is relevant content from the knowledge base.",
             score: 0.95,
             source: "test.md",
             metadata: %{line: 10}
           },
           %{
             id: "chunk_2",
             content: "More relevant information here.",
             score: 0.87,
             source: "test.md",
             metadata: %{line: 25}
           }
         ],
         query: query,
         strategy: :mock_hybrid,
         timing_ms: 10
       }}
    end

    @impl true
    def strategy_name, do: :mock_hybrid

    @impl true
    def required_adapters, do: [:vector_store, :embedder]

    @impl true
    def supports_embedding?, do: true

    @impl true
    def supports_text_query?, do: true
  end

  defmodule MockChunker do
    @moduledoc "Mock Chunker adapter for tests"
    @behaviour PortfolioCore.Ports.Chunker

    @impl true
    def chunk(text, _format, _config) do
      # Simple mock chunking - split on double newlines
      chunks = String.split(text, ~r/\n\n+/, trim: true)

      {:ok,
       Enum.with_index(chunks, fn chunk_text, idx ->
         byte_len = byte_size(chunk_text)

         %{
           content: chunk_text,
           index: idx,
           start_byte: 0,
           end_byte: byte_len,
           start_offset: 0,
           end_offset: String.length(chunk_text),
           metadata: %{}
         }
       end)}
    end

    @impl true
    def estimate_chunks(text, _config) do
      # Rough estimate - returns integer directly per callback spec
      max(1, div(String.length(text), 500))
    end
  end
end
