defmodule Command.FlowStone.Resources.AgentRunner do
  @moduledoc """
  LLM provider abstraction for prompt execution.

  Provides a unified interface for executing prompts across different
  LLM providers (Claude, Codex). The actual provider implementation
  is resolved at setup time based on configuration.

  ## Configuration

  - `:provider` - `:claude` | `:codex` (default: `:claude`)
  - `:model` - Model identifier (provider-specific default)
  - `:tools` - List of allowed tool names
  - `:permission_mode` - `:accept_edits` | `:review_edits` | `:reject_edits`
  - `:execution_mode` - `:per_repo` | `:workspace` (default: `:per_repo`)
  - `:workspace_root` - Absolute path for workspace mode (must contain target repos)

  ## Workspace Mode

  When execution_mode == :workspace, the adapter should use workspace_root as
  the working directory and avoid repo-specific context (current_repo nil).

  ## Streaming

  The stream/3 function returns an Elixir Stream that yields normalized
  events. Event normalization is handled by the provider adapter.

  ## Example

      config = %{
        provider: :claude,
        model: "claude-sonnet-4-20250514",
        tools: ["Read", "Write", "Edit", "Bash"],
        permission_mode: :accept_edits,
        execution_mode: :per_repo
      }

      {:ok, runner} = AgentRunner.setup(config)

      # Check connectivity
      :ok = AgentRunner.ping(runner)

      # Execute a prompt (returns a stream of events)
      stream = AgentRunner.stream(runner, "Write a hello world function", [])
      events = Enum.to_list(stream)
  """

  use FlowStone.Resource

  require Logger

  @type provider :: :claude | :codex

  @type t :: %{
          provider: provider(),
          model: String.t() | nil,
          tools: [String.t()],
          permission_mode: atom() | nil,
          execution_mode: :per_repo | :workspace,
          workspace_root: String.t() | nil,
          adapter: module()
        }

  @valid_providers [:claude, :codex]

  @impl true
  def setup(config) do
    provider = config[:provider] || :claude
    model = config[:model]
    tools = config[:tools] || []
    permission_mode = config[:permission_mode]
    execution_mode = config[:execution_mode] || :per_repo
    workspace_root = config[:workspace_root]

    if provider in @valid_providers do
      adapter = resolve_adapter(provider)

      {:ok,
       %{
         provider: provider,
         model: model,
         tools: tools,
         permission_mode: permission_mode,
         execution_mode: execution_mode,
         workspace_root: workspace_root,
         adapter: adapter
       }}
    else
      {:error, :invalid_provider}
    end
  end

  @impl true
  def health_check(runner) do
    case ping(runner) do
      :ok -> :healthy
      {:error, reason} -> {:unhealthy, reason}
    end
  end

  @doc ~S"""
  Check connectivity to the LLM provider.

  Returns `:ok` if the provider is reachable, `{:error, reason}` otherwise.

  ## Example

      case AgentRunner.ping(runner) do
        :ok -> IO.puts("Provider is healthy")
        {:error, err} -> IO.puts("Provider error: #{inspect(err)}")
      end
  """
  @spec ping(t()) :: :ok | {:error, term()}
  def ping(%{provider: _provider, adapter: _adapter}) do
    # NOTE: This is a stub implementation for MVP
    # When actual provider integration is implemented, this should:
    # 1. Make a lightweight API call to verify connectivity
    # 2. Check API key validity
    # 3. Verify model availability
    #
    # For now, we assume the provider is available
    :ok
  end

  @doc ~S"""
  Get the current configuration.

  Returns a map with the runner's configuration.

  ## Example

      cfg = AgentRunner.get_config(runner)
      IO.puts("Using provider: #{cfg.provider}")
      IO.puts("Using model: #{cfg.model}")
  """
  @spec get_config(t()) :: map()
  def get_config(runner) do
    %{
      provider: runner.provider,
      model: runner.model,
      tools: runner.tools,
      permission_mode: runner.permission_mode,
      execution_mode: runner.execution_mode,
      workspace_root: runner.workspace_root
    }
  end

  @doc """
  Execute a prompt and return a stream of normalized events.

  Returns a Stream that yields event maps. This is a stub implementation
  for MVP; actual provider integration will yield real events.

  ## Parameters

  - `runner` - The agent runner state
  - `prompt_content` - The prompt text to execute
  - `opts` - Optional keyword list with execution options
    - `:model` - Override the default model
    - `:temperature` - Temperature setting
    - `:max_tokens` - Maximum tokens to generate
    - `:current_repo` - Repository context (for per_repo mode)

  ## Example

      stream = AgentRunner.stream(runner, "Explain recursion", model: "claude-opus-4")

      Enum.each(stream, fn event ->
        IO.inspect(event)
      end)

  ## Event Format

  Events are maps with at least a `:type` key. Common event types:
  - `%{type: :start, timestamp: ~U[...]}`
  - `%{type: :content_block_delta, delta: %{text: "..."}}`
  - `%{type: :tool_use, tool: "Read", input: %{...}}`
  - `%{type: :complete, usage: %{input_tokens: 100, output_tokens: 200}}`
  - `%{type: :error, error: "..."}}`
  """
  @spec stream(t(), String.t(), keyword()) :: Enumerable.t()
  def stream(%{adapter: _adapter} = _runner, _prompt_content, _opts \\ []) do
    # NOTE: This is a stub implementation for MVP
    # When actual provider integration is implemented, this should:
    # 1. Call adapter.stream(prompt_content, opts)
    # 2. Return a Stream that yields normalized events
    # 3. Handle errors and retries according to policy
    #
    # For now, return an empty stream
    Stream.resource(
      fn -> :ok end,
      fn :ok -> {:halt, :ok} end,
      fn :ok -> :ok end
    )
  end

  # Private helpers

  defp resolve_adapter(:claude) do
    # NOTE: This will be replaced with actual adapter modules when implemented
    # For now, use a placeholder module name
    Command.FlowStone.Resources.AgentRunner.ClaudeAdapter
  end

  defp resolve_adapter(:codex) do
    # NOTE: This will be replaced with actual adapter modules when implemented
    # For now, use a placeholder module name
    Command.FlowStone.Resources.AgentRunner.CodexAdapter
  end
end
