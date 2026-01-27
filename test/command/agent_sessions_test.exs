defmodule Command.AgentSessionsTest do
  use ExUnit.Case, async: true

  alias Command.AgentSessions

  describe "resolve_agent_adapter/1" do
    test "resolves :claude to portfolio adapter" do
      adapter = AgentSessions.resolve_agent_adapter(:claude)
      assert adapter == PortfolioIndex.Adapters.AgentSession.Claude
    end

    test "resolves :codex to portfolio adapter" do
      adapter = AgentSessions.resolve_agent_adapter(:codex)
      assert adapter == PortfolioIndex.Adapters.AgentSession.Codex
    end

    test "raises for unknown provider" do
      assert_raise ArgumentError, ~r/Unknown agent provider/, fn ->
        AgentSessions.resolve_agent_adapter(:unknown)
      end
    end
  end

  describe "start_session/3" do
    test "delegates to resolved adapter" do
      assert function_exported?(Command.AgentSessions, :start_session, 3)
    end
  end

  describe "execute/4" do
    test "delegates to resolved adapter" do
      assert function_exported?(Command.AgentSessions, :execute, 4)
    end
  end

  describe "cancel/3" do
    test "delegates to resolved adapter" do
      assert function_exported?(Command.AgentSessions, :cancel, 3)
    end
  end

  describe "end_session/2" do
    test "delegates to resolved adapter" do
      assert function_exported?(Command.AgentSessions, :end_session, 2)
    end
  end
end
