defmodule Command.ApplicationTest do
  @moduledoc """
  Tests for Command.Application startup behavior.
  """
  use Command.SupertesterCase, async: false

  alias Command.Portfolio
  alias Command.Test.PortfolioMocks.{MockEmbedder, MockLLM, MockRetriever, MockVectorStore}

  describe "adapter validation" do
    test "validate_adapters!/0 succeeds when all required adapters registered" do
      # Register all required adapters
      :ok = PortfolioCore.Registry.register(:vector_store, MockVectorStore, %{}, %{})
      :ok = PortfolioCore.Registry.register(:embedder, MockEmbedder, %{}, %{})
      :ok = PortfolioCore.Registry.register(:llm, MockLLM, %{}, %{})
      :ok = PortfolioCore.Registry.register(:retriever, MockRetriever, %{}, %{})

      assert :ok = Portfolio.validate_adapters!()
    end

    test "validate_adapters!/0 raises when adapter missing" do
      # Register only some adapters
      :ok = PortfolioCore.Registry.register(:vector_store, MockVectorStore, %{}, %{})
      :ok = PortfolioCore.Registry.register(:embedder, MockEmbedder, %{}, %{})
      # Missing :llm and :retriever

      assert_raise RuntimeError, ~r/Missing required adapter/, fn ->
        Portfolio.validate_adapters!()
      end
    end

    test "required_adapters_present?/0 returns false when adapters missing" do
      refute Portfolio.required_adapters_present?()
    end

    test "required_adapters_present?/0 returns true when all present" do
      :ok = PortfolioCore.Registry.register(:vector_store, MockVectorStore, %{}, %{})
      :ok = PortfolioCore.Registry.register(:embedder, MockEmbedder, %{}, %{})
      :ok = PortfolioCore.Registry.register(:llm, MockLLM, %{}, %{})
      :ok = PortfolioCore.Registry.register(:retriever, MockRetriever, %{}, %{})

      assert Portfolio.required_adapters_present?()
    end
  end
end
