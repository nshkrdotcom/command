defmodule Command.AITest do
  use ExUnit.Case, async: true

  alias Command.AI

  describe "function exports" do
    test "generate/2 delegates to portfolio LLM adapter" do
      assert function_exported?(AI, :generate, 2)
    end

    test "stream/2 delegates to portfolio LLM adapter" do
      assert function_exported?(AI, :stream, 2)
    end

    test "embed/2 delegates to portfolio Embedder adapter" do
      assert function_exported?(AI, :embed, 2)
    end

    test "embed_batch/2 delegates to portfolio Embedder adapter" do
      assert function_exported?(AI, :embed_batch, 2)
    end

    test "classify/3 delegates to portfolio LLM adapter" do
      assert function_exported?(AI, :classify, 3)
    end

    test "chat_completion/2 delegates to portfolio LLM adapter" do
      assert function_exported?(AI, :chat_completion, 2)
    end
  end
end
