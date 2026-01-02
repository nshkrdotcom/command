defmodule Command.PortfolioTest do
  @moduledoc """
  Tests for portfolio integration.

  These tests verify that Command correctly integrates with
  portfolio_core and portfolio_index for RAG capabilities.
  """
  use Command.SupertesterCase, async: false

  alias Command.Portfolio
  alias Command.Test.PortfolioMocks.{MockEmbedder, MockLLM, MockRetriever, MockVectorStore}

  describe "adapter/1" do
    test "returns registered adapter" do
      # Register mock adapters for this test
      :ok = PortfolioCore.Registry.register(:vector_store, MockVectorStore, %{}, %{})

      assert {adapter, _config} = Portfolio.adapter!(:vector_store)
      assert adapter == MockVectorStore
    end

    test "raises when adapter not registered" do
      # Ensure adapter is not registered
      PortfolioCore.Registry.unregister(:nonexistent_port)

      assert_raise ArgumentError, fn ->
        Portfolio.adapter!(:nonexistent_port)
      end
    end
  end

  describe "required_adapters_present?/0" do
    setup do
      # Register all required mock adapters
      :ok = PortfolioCore.Registry.register(:vector_store, MockVectorStore, %{}, %{})
      :ok = PortfolioCore.Registry.register(:embedder, MockEmbedder, %{}, %{})
      :ok = PortfolioCore.Registry.register(:llm, MockLLM, %{}, %{})
      :ok = PortfolioCore.Registry.register(:retriever, MockRetriever, %{}, %{})

      :ok
    end

    test "returns true when all required adapters present" do
      assert Portfolio.required_adapters_present?()
    end

    test "returns false when adapter missing" do
      PortfolioCore.Registry.unregister(:embedder)
      refute Portfolio.required_adapters_present?()
    end
  end

  describe "validate_adapters!/0" do
    setup do
      :ok = PortfolioCore.Registry.register(:vector_store, MockVectorStore, %{}, %{})
      :ok = PortfolioCore.Registry.register(:embedder, MockEmbedder, %{}, %{})
      :ok = PortfolioCore.Registry.register(:llm, MockLLM, %{}, %{})
      :ok = PortfolioCore.Registry.register(:retriever, MockRetriever, %{}, %{})

      :ok
    end

    test "returns :ok when all adapters valid" do
      assert :ok = Portfolio.validate_adapters!()
    end

    test "raises when adapter missing" do
      PortfolioCore.Registry.unregister(:llm)

      assert_raise RuntimeError, ~r/Missing required adapter: llm/, fn ->
        Portfolio.validate_adapters!()
      end
    end
  end

  describe "embed/2" do
    setup do
      :ok = PortfolioCore.Registry.register(:embedder, MockEmbedder, %{}, %{})
      :ok
    end

    test "generates embedding for text" do
      assert {:ok, embedding} = Portfolio.embed("test text")
      assert is_list(embedding)
      assert length(embedding) == 1536
    end

    test "generates batch embeddings" do
      texts = ["text 1", "text 2", "text 3"]
      assert {:ok, embeddings} = Portfolio.embed_batch(texts)
      assert length(embeddings) == 3
    end
  end

  describe "complete/2" do
    setup do
      :ok = PortfolioCore.Registry.register(:llm, MockLLM, %{}, %{})
      :ok
    end

    test "generates LLM completion" do
      messages = [%{role: "user", content: "Hello"}]

      assert {:ok, response} = Portfolio.complete(messages)
      assert response.content == "This is a mock LLM response."
      assert response.usage.input_tokens == 10
      assert response.usage.output_tokens == 20
    end

    test "accepts options" do
      messages = [%{role: "user", content: "Hello"}]

      assert {:ok, response} = Portfolio.complete(messages, model: "mock-model", temperature: 0.5)
      assert response.content
    end
  end

  describe "retrieve/2" do
    setup do
      :ok = PortfolioCore.Registry.register(:retriever, MockRetriever, %{}, %{})
      :ok
    end

    test "retrieves relevant context" do
      assert {:ok, chunks} = Portfolio.retrieve("test query")
      assert length(chunks) == 2
      assert hd(chunks).score == 0.95
    end

    test "accepts context options" do
      context = %{index_id: "my_index"}

      assert {:ok, chunks} = Portfolio.retrieve("test query", context, k: 5)
      assert is_list(chunks)
    end
  end
end
