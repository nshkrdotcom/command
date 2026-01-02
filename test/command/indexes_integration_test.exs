defmodule Command.IndexesIntegrationTest do
  @moduledoc """
  Integration tests for Command.Indexes using portfolio adapters.

  These tests verify that Command.Indexes correctly delegates to
  portfolio_core/portfolio_index for vector operations.
  """
  use Command.SupertesterCase, async: false

  alias Command.Indexes
  alias Command.Test.PortfolioMocks.{MockChunker, MockEmbedder, MockRetriever, MockVectorStore}

  setup do
    # Register mock adapters
    :ok =
      PortfolioCore.Registry.register(:vector_store, MockVectorStore, %{repo: Command.Repo}, %{})

    :ok = PortfolioCore.Registry.register(:embedder, MockEmbedder, %{}, %{})
    :ok = PortfolioCore.Registry.register(:chunker, MockChunker, %{}, %{})
    :ok = PortfolioCore.Registry.register(:retriever, MockRetriever, %{}, %{})

    :ok
  end

  describe "search/3" do
    test "searches using portfolio retriever" do
      # The new Indexes.search delegates to portfolio
      assert {:ok, results} = Indexes.search("my_index", "test query")
      assert is_list(results)
    end

    test "accepts k option" do
      assert {:ok, results} = Indexes.search("my_index", "test query", k: 5)
      assert is_list(results)
    end

    test "accepts filter options" do
      assert {:ok, results} =
               Indexes.search("my_index", "test query",
                 k: 10,
                 filters: %{language: "elixir"}
               )

      assert is_list(results)
    end
  end

  describe "embed_and_search/3" do
    test "embeds query and searches" do
      assert {:ok, results} = Indexes.embed_and_search("my_index", "test query")
      assert is_list(results)
    end
  end

  describe "embed_text/1" do
    test "generates embedding via portfolio embedder" do
      assert {:ok, embedding} = Indexes.embed_text("test text")
      assert is_list(embedding)
      assert length(embedding) == 1536
    end
  end

  describe "chunk_text/2" do
    test "chunks text via portfolio chunker" do
      text = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."

      assert {:ok, chunks} = Indexes.chunk_text(text)
      assert is_list(chunks)
      assert length(chunks) == 3
    end

    test "accepts chunking options" do
      text = "Some long text that needs chunking..."

      assert {:ok, chunks} = Indexes.chunk_text(text, chunk_size: 100, overlap: 20)
      assert is_list(chunks)
    end
  end

  describe "store_embedding/4" do
    test "stores embedding in vector store" do
      embedding = List.duplicate(0.1, 1536)
      metadata = %{source: "test.md", content: "test content"}

      assert :ok = Indexes.store_embedding("my_index", "chunk_1", embedding, metadata)
    end
  end

  describe "create_index/2" do
    test "creates index via portfolio vector store" do
      assert :ok = Indexes.create_index("new_index", dimensions: 1536, metric: :cosine)
    end
  end

  describe "delete_index/1" do
    test "deletes index via portfolio vector store" do
      assert :ok = Indexes.delete_index("old_index")
    end
  end

  describe "index_stats/1" do
    test "returns stats from portfolio vector store" do
      assert {:ok, stats} = Indexes.index_stats("my_index")
      assert stats.count == 100
      assert stats.dimensions == 1536
    end
  end
end
