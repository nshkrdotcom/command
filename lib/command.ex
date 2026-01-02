defmodule Command do
  @moduledoc """
  Command - Core library for AI agent orchestration.

  Command provides a unified workbench for running, tracking, and
  orchestrating AI agents against your data and code. It includes:

  - **Sessions**: Persistent, resumable contexts for agent work
  - **Agents**: Multi-provider LLM integration with full lifecycle tracking
  - **Workflows**: DAG-based orchestration with approval gates
  - **Indexes**: RAG context management with vector search
  - **Approvals**: Human-in-the-loop approval workflows
  - **Costs**: Detailed cost tracking and reporting

  ## Quick Start

      # Create a user
      {:ok, user} = Command.Accounts.create_user(%{email: "dev@example.com"})

      # Create a session
      {:ok, session} = Command.Sessions.create_session(user, %{
        name: "Code Review",
        purpose: "Review PR #123"
      })

      # Record an agent call
      {:ok, call} = Command.Agents.create_agent_call(session, %{
        provider: "anthropic",
        model: "claude-sonnet-4-20250514",
        prompt_messages: [%{role: "user", content: "Review this code..."}]
      })

  ## Architecture

  Command follows a hexagonal architecture with clear separation between:

  - **Schemas**: Ecto schemas representing database tables
  - **Contexts**: Business logic modules organizing domain operations
  - **Repo**: Database access layer with pagination helpers

  All IDs are UUIDs for distributed-friendly operation.
  """

  @doc """
  Returns the application version.
  """
  @spec version() :: String.t()
  def version, do: "0.1.0"
end
