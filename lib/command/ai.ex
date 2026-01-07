defmodule Command.AI do
  @moduledoc """
  Command AI context.

  Provides a thin wrapper around `Altar.AI.Client` with Command-specific
  configuration loading and convenience helpers.

  ## Examples

      {:ok, response} = Command.AI.generate("Summarize this session")
      IO.puts(response.content)
  """

  alias Altar.AI.{Client, Config}

  @type t :: Client.t()
  @type chat_completion_response :: %{
          content: String.t(),
          model: String.t(),
          provider: atom(),
          finish_reason: atom(),
          metadata: %{total_tokens: non_neg_integer()}
        }

  @doc """
  Builds an `Altar.AI.Client` using Command configuration.

  Falls back to `:altar_ai` application config when Command has no profiles.
  """
  @spec client(keyword()) :: t()
  def client(opts \\ []) do
    config = Keyword.get(opts, :config, load_config())
    Client.new(config: config)
  end

  @doc """
  Generates text using the configured adapter.
  """
  @spec generate(String.t(), keyword()) :: {:ok, Altar.AI.Response.t()} | {:error, term()}
  def generate(prompt, opts \\ []) do
    {client, call_opts} = pop_client(opts)
    Client.generate(client, prompt, call_opts)
  end

  @doc """
  Streams generated text using the configured adapter.
  """
  @spec stream(String.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream(prompt, opts \\ []) do
    {client, call_opts} = pop_client(opts)
    Client.stream(client, prompt, call_opts)
  end

  @doc """
  Generates an embedding for a single text input.
  """
  @spec embed(String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}
  def embed(text, opts \\ []) do
    {client, call_opts} = pop_client(opts)
    Client.embed(client, text, call_opts)
  end

  @doc """
  Generates embeddings for a batch of texts.
  """
  @spec embed_batch([String.t()], keyword()) :: {:ok, [[float()]]} | {:error, term()}
  def embed_batch(texts, opts \\ []) do
    {client, call_opts} = pop_client(opts)
    Client.batch_embed(client, texts, call_opts)
  end

  @doc """
  Classifies text into one of the provided labels.
  """
  @spec classify(String.t(), [String.t()], keyword()) ::
          {:ok, Altar.AI.Classification.t()} | {:error, term()}
  def classify(text, labels, opts \\ []) do
    {client, call_opts} = pop_client(opts)
    Client.classify(client, text, labels, call_opts)
  end

  @doc """
  ReqLLM-compatible chat completion interface.
  """
  @spec chat_completion(map(), keyword()) :: {:ok, chat_completion_response()} | {:error, term()}
  def chat_completion(params, opts \\ []) do
    {client, call_opts} = pop_client(opts)
    Client.chat_completion(client, params, call_opts)
  end

  defp pop_client(opts) do
    case Keyword.pop(opts, :client) do
      {nil, call_opts} -> {client(), call_opts}
      {client, call_opts} -> {client, call_opts}
    end
  end

  defp load_config do
    command_config = Config.from_application_env(:command)

    config =
      if map_size(command_config.profiles) == 0 do
        Config.from_application_env(:altar_ai)
      else
        command_config
      end

    normalize_config(config)
  end

  defp normalize_config(%Config{} = config) do
    profiles =
      config.profiles
      |> Enum.map(fn {name, opts} -> {name, normalize_profile_opts(opts)} end)
      |> Map.new()

    %{config | profiles: profiles}
  end

  defp normalize_profile_opts(opts) when is_map(opts) do
    opts
    |> Enum.into([])
    |> normalize_profile_opts()
  end

  defp normalize_profile_opts(opts) when is_list(opts) do
    adapter = Keyword.get(opts, :adapter)
    adapter_opts = Keyword.get(opts, :adapter_opts, [])

    case adapter do
      nil ->
        opts

      adapter when is_atom(adapter) ->
        _ = Code.ensure_loaded(adapter)

        built_adapter =
          cond do
            function_exported?(adapter, :new, 1) -> adapter.new(adapter_opts)
            function_exported?(adapter, :new, 0) -> adapter.new()
            function_exported?(adapter, :default, 0) -> adapter.default()
            true -> adapter
          end

        opts
        |> Keyword.put(:adapter, built_adapter)
        |> Keyword.delete(:adapter_opts)

      _struct ->
        opts
    end
  end
end
