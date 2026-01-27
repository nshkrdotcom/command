defmodule Command.FlowStone.Resources.ResourceSetupTest do
  use Command.DataCase, async: false

  alias Command.FlowStone.Resources.ResourceSetup
  alias FlowStone.Resources

  @test_log_dir System.tmp_dir!() <> "/flowstone_resource_setup_test"

  setup do
    # Start FlowStone.Resources GenServer for testing
    {:ok, pid} = start_supervised({Resources, name: :test_resources, resources: %{}})

    # Clean up test directory
    if File.exists?(@test_log_dir) do
      File.rm_rf!(@test_log_dir)
    end

    on_exit(fn ->
      if File.exists?(@test_log_dir) do
        File.rm_rf!(@test_log_dir)
      end
    end)

    %{resources_pid: pid}
  end

  describe "register/2" do
    test "registers all resources with FlowStone.Resources" do
      run_id = Ecto.UUID.generate()

      # Create a minimal prompt_set configuration
      prompt_set = %{
        config: %{
          default_provider: :claude,
          default_model: "claude-sonnet-4-20250514",
          allowed_tools: ["Read", "Write", "Edit", "Bash"],
          log_dir: @test_log_dir,
          project_dir: "/home/project/test"
        }
      }

      assert :ok = ResourceSetup.register(prompt_set, run_id, server: :test_resources)

      # Verify resources were registered
      assert {:ok, _agent_runner} = Resources.get(:agent_runner, :test_resources)
      assert {:ok, _artifact_store} = Resources.get(:artifact_store, :test_resources)
      assert {:ok, _progress} = Resources.get(:progress, :test_resources)
    end

    test "registered resources receive correct configuration" do
      run_id = Ecto.UUID.generate()

      prompt_set = %{
        config: %{
          default_provider: :codex,
          default_model: "codex-model",
          allowed_tools: ["Bash"],
          log_dir: @test_log_dir,
          project_dir: "/home/project/test"
        }
      }

      assert :ok = ResourceSetup.register(prompt_set, run_id, server: :test_resources)

      # Get agent_runner and verify config
      {:ok, agent_runner} = Resources.get(:agent_runner, :test_resources)
      config = Command.FlowStone.Resources.AgentRunner.get_config(agent_runner)

      assert config.provider == :codex
      assert config.model == "codex-model"
      assert config.tools == ["Bash"]
    end

    test "progress resource has correct run_id" do
      run_id = Ecto.UUID.generate()

      prompt_set = %{
        config: %{
          default_provider: :claude,
          default_model: "claude-sonnet-4-20250514",
          allowed_tools: [],
          log_dir: @test_log_dir,
          project_dir: "/home/project/test"
        }
      }

      assert :ok = ResourceSetup.register(prompt_set, run_id, server: :test_resources)

      {:ok, progress} = Resources.get(:progress, :test_resources)
      assert progress.run_id == run_id
    end

    test "artifact_store has correct log_dir and run_id" do
      run_id = Ecto.UUID.generate()

      prompt_set = %{
        config: %{
          default_provider: :claude,
          default_model: "claude-sonnet-4-20250514",
          allowed_tools: [],
          log_dir: @test_log_dir,
          project_dir: "/home/project/test"
        }
      }

      assert :ok = ResourceSetup.register(prompt_set, run_id, server: :test_resources)

      {:ok, artifact_store} = Resources.get(:artifact_store, :test_resources)
      assert artifact_store.log_dir == @test_log_dir
      assert artifact_store.run_id == run_id
    end
  end

  describe "resource health checks" do
    test "all registered resources are healthy" do
      run_id = Ecto.UUID.generate()

      prompt_set = %{
        config: %{
          default_provider: :claude,
          default_model: "claude-sonnet-4-20250514",
          allowed_tools: ["Read"],
          log_dir: @test_log_dir,
          project_dir: "/home/project/test"
        }
      }

      assert :ok = ResourceSetup.register(prompt_set, run_id, server: :test_resources)

      # Check health of each resource
      {:ok, agent_runner} = Resources.get(:agent_runner, :test_resources)

      assert :healthy =
               Command.FlowStone.Resources.AgentRunner.health_check(agent_runner)

      {:ok, artifact_store} = Resources.get(:artifact_store, :test_resources)

      assert :healthy =
               Command.FlowStone.Resources.ArtifactStore.health_check(artifact_store)

      {:ok, progress} = Resources.get(:progress, :test_resources)

      assert :healthy =
               Command.FlowStone.Resources.ProgressTracker.health_check(progress)
    end
  end

  describe "resource teardown" do
    test "teardown is called for all resources" do
      run_id = Ecto.UUID.generate()

      prompt_set = %{
        config: %{
          default_provider: :claude,
          default_model: "claude-sonnet-4-20250514",
          allowed_tools: [],
          log_dir: @test_log_dir,
          project_dir: "/home/project/test"
        }
      }

      assert :ok = ResourceSetup.register(prompt_set, run_id, server: :test_resources)

      # Get all resources
      {:ok, agent_runner} = Resources.get(:agent_runner, :test_resources)
      {:ok, artifact_store} = Resources.get(:artifact_store, :test_resources)
      {:ok, progress} = Resources.get(:progress, :test_resources)

      # Teardown should succeed for all
      assert :ok = Command.FlowStone.Resources.AgentRunner.teardown(agent_runner)

      assert :ok =
               Command.FlowStone.Resources.ArtifactStore.teardown(artifact_store)

      assert :ok = Command.FlowStone.Resources.ProgressTracker.teardown(progress)
    end
  end
end
