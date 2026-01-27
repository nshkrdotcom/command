defmodule Command.FlowStone.Resources.AgentRunnerTest do
  use Command.DataCase, async: true

  alias Command.FlowStone.Resources.AgentRunner

  describe "setup/1" do
    test "returns {:ok, runner_state} with provider config" do
      config = %{
        provider: :claude,
        model: "claude-sonnet-4-20250514",
        tools: ["Read", "Write", "Edit"],
        permission_mode: :accept_edits,
        execution_mode: :per_repo
      }

      assert {:ok, runner} = AgentRunner.setup(config)
      assert runner.provider == :claude
      assert runner.model == "claude-sonnet-4-20250514"
      assert runner.tools == ["Read", "Write", "Edit"]
      assert runner.permission_mode == :accept_edits
      assert runner.execution_mode == :per_repo
      assert is_atom(runner.adapter)
    end

    test "defaults provider to :claude when not specified" do
      config = %{
        model: "claude-sonnet-4-20250514"
      }

      assert {:ok, runner} = AgentRunner.setup(config)
      assert runner.provider == :claude
    end

    test "validates provider is :claude or :codex" do
      valid_providers = [:claude, :codex]

      for provider <- valid_providers do
        config = %{provider: provider}
        assert {:ok, runner} = AgentRunner.setup(config)
        assert runner.provider == provider
      end
    end

    test "returns {:error, :invalid_provider} for unknown provider" do
      config = %{provider: :invalid_provider}

      assert {:error, :invalid_provider} = AgentRunner.setup(config)
    end

    test "persists execution_mode in runner_state" do
      config = %{
        provider: :claude,
        execution_mode: :workspace
      }

      assert {:ok, runner} = AgentRunner.setup(config)
      assert runner.execution_mode == :workspace
    end

    test "persists workspace_root in runner_state when provided" do
      config = %{
        provider: :claude,
        execution_mode: :workspace,
        workspace_root: "/home/project/workspace"
      }

      assert {:ok, runner} = AgentRunner.setup(config)
      assert runner.workspace_root == "/home/project/workspace"
    end

    test "defaults execution_mode to :per_repo when not specified" do
      config = %{
        provider: :claude
      }

      assert {:ok, runner} = AgentRunner.setup(config)
      assert runner.execution_mode == :per_repo
    end

    test "allows nil workspace_root when execution_mode is :per_repo" do
      config = %{
        provider: :claude,
        execution_mode: :per_repo,
        workspace_root: nil
      }

      assert {:ok, runner} = AgentRunner.setup(config)
      assert runner.workspace_root == nil
    end
  end

  describe "ping/1" do
    setup do
      config = %{provider: :claude}
      {:ok, runner} = AgentRunner.setup(config)
      %{runner: runner}
    end

    test "returns :ok for healthy connection (stubbed)", %{runner: runner} do
      # This is stubbed for MVP - actual provider integration is separate
      assert :ok = AgentRunner.ping(runner)
    end
  end

  describe "get_config/1" do
    test "returns current provider configuration" do
      config = %{
        provider: :codex,
        model: "codex-default",
        tools: ["Bash", "Read"],
        permission_mode: :review_edits,
        execution_mode: :workspace,
        workspace_root: "/home/workspace"
      }

      {:ok, runner} = AgentRunner.setup(config)

      result = AgentRunner.get_config(runner)

      assert result.provider == :codex
      assert result.model == "codex-default"
      assert result.tools == ["Bash", "Read"]
      assert result.permission_mode == :review_edits
      assert result.execution_mode == :workspace
      assert result.workspace_root == "/home/workspace"
    end
  end

  describe "stream/3" do
    setup do
      config = %{provider: :claude}
      {:ok, runner} = AgentRunner.setup(config)
      %{runner: runner}
    end

    test "returns stream of events (stubbed implementation)", %{runner: runner} do
      prompt_content = "Write a hello world function in Elixir"
      opts = [model: "claude-sonnet-4-20250514"]

      # For MVP, this returns an empty stream
      result = AgentRunner.stream(runner, prompt_content, opts)

      assert is_function(result)
      # The stream should be enumerable
      events = Enum.to_list(result)
      assert is_list(events)
    end

    test "accepts empty opts", %{runner: runner} do
      prompt_content = "Test prompt"

      result = AgentRunner.stream(runner, prompt_content)

      assert is_function(result)
      assert is_list(Enum.to_list(result))
    end
  end

  describe "teardown/1" do
    test "returns :ok" do
      config = %{provider: :claude}
      {:ok, runner} = AgentRunner.setup(config)

      assert :ok = AgentRunner.teardown(runner)
    end
  end

  describe "health_check/1" do
    test "calls ping and returns :healthy" do
      config = %{provider: :claude}
      {:ok, runner} = AgentRunner.setup(config)

      assert :healthy = AgentRunner.health_check(runner)
    end
  end

  describe "adapter resolution" do
    test "resolves adapter module for :claude provider" do
      config = %{provider: :claude}
      {:ok, runner} = AgentRunner.setup(config)

      # The adapter module should be resolved (even if stubbed)
      assert is_atom(runner.adapter)
    end

    test "resolves adapter module for :codex provider" do
      config = %{provider: :codex}
      {:ok, runner} = AgentRunner.setup(config)

      # The adapter module should be resolved (even if stubbed)
      assert is_atom(runner.adapter)
    end
  end
end
