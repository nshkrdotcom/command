defmodule Command.AI do
  @moduledoc """
  Command AI context.

  Provides a thin wrapper around portfolio adapters for LLM and embedding
  operations. Delegates to `Command.Portfolio` for all AI capabilities.

  ## Examples

      {:ok, response} = Command.AI.generate("Summarize this session")

      {:ok, embedding} = Command.AI.embed("some text")

      {:ok, classification} = Command.AI.classify("I love Elixir", ["positive", "negative"])
  """

  @type chat_completion_response :: %{
          content: String.t(),
          model: String.t(),
          provider: atom(),
          finish_reason: atom(),
          metadata: %{total_tokens: non_neg_integer()}
        }

  @doc """
  Generates text using the configured portfolio LLM adapter.
  """
  @spec generate(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def generate(prompt, opts \\ []) do
    messages = [%{role: :user, content: prompt}]
    Command.Portfolio.complete(messages, opts)
  end

  @doc """
  Streams generated text using the configured portfolio LLM adapter.
  """
  @spec stream(String.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream(prompt, opts \\ []) do
    messages = [%{role: :user, content: prompt}]
    Command.Portfolio.stream(messages, opts)
  end

  @doc """
  Generates an embedding for a single text input.
  """
  @spec embed(String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}
  def embed(text, opts \\ []) do
    Command.Portfolio.embed(text, opts)
  end

  @doc """
  Generates embeddings for a batch of texts.
  """
  @spec embed_batch([String.t()], keyword()) :: {:ok, [[float()]]} | {:error, term()}
  def embed_batch(texts, opts \\ []) do
    Command.Portfolio.embed_batch(texts, opts)
  end

  @doc """
  Classifies text into one of the provided labels.
  """
  @spec classify(String.t(), [String.t()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def classify(text, labels, opts \\ []) do
    prompt = build_classification_prompt(text, labels)
    messages = [%{role: :user, content: prompt}]

    with {:ok, result} <- Command.Portfolio.complete(messages, opts) do
      parse_classification(result, labels)
    end
  end

  @doc """
  Chat completion interface using portfolio LLM adapter.
  """
  @spec chat_completion(map(), keyword()) :: {:ok, chat_completion_response()} | {:error, term()}
  def chat_completion(params, opts \\ []) do
    messages = Map.get(params, :messages, Map.get(params, "messages", []))
    Command.Portfolio.complete(messages, opts)
  end

  # Private helpers

  defp build_classification_prompt(text, labels) do
    labels_str = Enum.join(labels, ", ")

    """
    Classify the following text into exactly one of these categories: #{labels_str}

    Text: #{text}

    Respond with ONLY the category label, nothing else.
    """
  end

  defp parse_classification(result, labels) do
    content =
      case result do
        %{content: content} when is_binary(content) -> String.trim(content)
        content when is_binary(content) -> String.trim(content)
        _ -> ""
      end

    label =
      Enum.find(labels, List.first(labels), fn label ->
        String.downcase(content) == String.downcase(label)
      end)

    {:ok, %{label: label, confidence: 1.0, raw_response: content}}
  end
end
