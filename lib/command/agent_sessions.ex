defmodule Command.AgentSessions do
  @moduledoc """
  Agent session management through portfolio.

  Provides stateful agent session access using the
  `PortfolioCore.Ports.AgentSession` port via portfolio_index adapters.

  This module replaces the former direct SDK adapters
  (`Command.Adapter.Claude` and `Command.Adapter.Codex`) with a unified
  delegation through the portfolio ecosystem.

  ## Usage

      # Start a Claude agent session
      {:ok, session_id} = Command.AgentSessions.start_session(:claude, "my-agent")

      # Execute a run within the session
      {:ok, result} = Command.AgentSessions.execute(:claude, session_id, %{prompt: "Hello"})

      # End the session
      :ok = Command.AgentSessions.end_session(:claude, session_id)

  ## Providers

  - `:claude` - Routes to `PortfolioIndex.Adapters.AgentSession.Claude`
  - `:codex` - Routes to `PortfolioIndex.Adapters.AgentSession.Codex`
  """

  @type provider :: :claude | :codex

  @doc """
  Start a new agent session.

  ## Parameters

    - `provider` - `:claude` or `:codex`
    - `agent_id` - Identifier for the agent type or configuration
    - `opts` - Session options passed to the adapter

  ## Returns

    - `{:ok, session_id}` - Session started successfully
    - `{:error, reason}` - Session could not be started
  """
  @spec start_session(provider(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def start_session(provider, agent_id, opts \\ []) do
    adapter = resolve_agent_adapter(provider)
    adapter.start_session(agent_id, opts)
  end

  @doc """
  Execute a run within an existing session.

  ## Parameters

    - `provider` - `:claude` or `:codex`
    - `session_id` - The session to execute within
    - `input` - Input data for the run
    - `opts` - Execution options (`:event_callback`, `:timeout`, `:max_turns`)

  ## Returns

    - `{:ok, run_result}` - Run completed successfully
    - `{:error, reason}` - Run failed
  """
  @spec execute(provider(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def execute(provider, session_id, input, opts \\ []) do
    adapter = resolve_agent_adapter(provider)
    adapter.execute(session_id, input, opts)
  end

  @doc """
  Cancel an in-progress run.

  ## Parameters

    - `provider` - `:claude` or `:codex`
    - `session_id` - The session containing the run
    - `run_id` - The ID of the run to cancel

  ## Returns

    - `{:ok, run_id}` - Cancellation initiated
    - `{:error, reason}` - Cancellation failed
  """
  @spec cancel(provider(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def cancel(provider, session_id, run_id) do
    adapter = resolve_agent_adapter(provider)
    adapter.cancel(session_id, run_id)
  end

  @doc """
  End a session and release associated resources.

  ## Parameters

    - `provider` - `:claude` or `:codex`
    - `session_id` - The session to end

  ## Returns

    - `:ok` - Session ended successfully
    - `{:error, reason}` - Session could not be ended
  """
  @spec end_session(provider(), String.t()) :: :ok | {:error, term()}
  def end_session(provider, session_id) do
    adapter = resolve_agent_adapter(provider)
    adapter.end_session(session_id)
  end

  @doc """
  Resolves a provider atom to its portfolio_index AgentSession adapter module.

  ## Parameters

    - `provider` - `:claude` or `:codex`

  ## Returns

  The adapter module for the given provider.

  ## Raises

  `ArgumentError` if the provider is unknown.
  """
  @spec resolve_agent_adapter(provider()) :: module()
  def resolve_agent_adapter(:claude),
    do: PortfolioIndex.Adapters.AgentSession.Claude

  def resolve_agent_adapter(:codex),
    do: PortfolioIndex.Adapters.AgentSession.Codex

  def resolve_agent_adapter(other),
    do: raise(ArgumentError, "Unknown agent provider: #{inspect(other)}")
end
