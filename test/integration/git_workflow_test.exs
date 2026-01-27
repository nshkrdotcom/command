defmodule Command.Integration.GitWorkflowTest do
  @moduledoc """
  End-to-end integration test for the VCS four-layer architecture.

  Tests the complete flow:
  1. FlowStone VCS resource setup
  2. Git adapter operations on a real temporary repo
  3. FlowStone step execution via Command.Steps.Git
  4. Telemetry event emission
  """
  use ExUnit.Case, async: false

  alias Command.FlowStone.Resources.VCS
  alias Command.Steps.Git
  alias PortfolioIndex.Adapters.VCS.Git, as: GitAdapter

  setup do
    # Create temporary git repository
    tmp_dir = System.tmp_dir!() |> Path.join("integration_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)

    System.cmd("git", ["init"], cd: tmp_dir, stderr_to_stdout: true)
    System.cmd("git", ["config", "user.name", "Integration Test"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "integration@test.com"], cd: tmp_dir)

    # Create initial commit
    initial_file = Path.join(tmp_dir, "README.md")
    File.write!(initial_file, "# Integration Test Repo\n")
    System.cmd("git", ["add", "README.md"], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "Initial commit"], cd: tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    %{repo: tmp_dir}
  end

  describe "commit workflow through FlowStone" do
    test "full status -> stage -> commit flow", %{repo: repo} do
      # 1. Setup VCS resource with real Git adapter
      assert {:ok, vcs_state} = VCS.setup(%{repo: repo, adapter: GitAdapter})

      # 2. Verify health check passes
      assert :healthy = VCS.health_check(vcs_state)

      # 3. Create a file to commit
      File.write!(Path.join(repo, "feature.txt"), "New feature content\n")

      # 4. Build FlowStone context with the VCS resource
      context = %FlowStone.Context{
        asset: :integration_test,
        partition: :default,
        run_id: "integration-#{:rand.uniform(1_000_000)}",
        resources: %{git: vcs_state},
        metadata: %{},
        started_at: DateTime.utc_now()
      }

      # 5. Check status via step - should be dirty
      assert {:ok, status_result} = Git.run(%{operation: :status}, context)
      assert status_result.status.is_dirty == true
      assert "feature.txt" in status_result.status.untracked_files

      # 6. Get uncommitted diff via step
      assert {:ok, diff_result} = Git.run(%{operation: :diff}, context)
      assert is_binary(diff_result.patch)

      # 7. Run commit step - stages all and commits
      assert {:ok, commit_result} =
               Git.run(
                 %{operation: :commit, message: "Add feature file"},
                 context
               )

      assert %{commit_hash: hash} = commit_result
      assert is_binary(hash)
      assert String.length(hash) == 40
      assert hash =~ ~r/^[0-9a-f]{40}$/

      # 8. Verify repo is now clean
      assert {:ok, clean_result} = Git.run(%{operation: :status}, context)
      assert clean_result.status.is_dirty == false

      # 9. Verify commit message via adapter directly
      {:ok, commit} = VCS.show(vcs_state, hash)
      assert commit.message == "Add feature file"
      assert commit.author == "Integration Test"

      # 10. Teardown
      assert :ok = VCS.teardown(vcs_state)
    end

    test "commit with no changes returns no_changes", %{repo: repo} do
      {:ok, vcs_state} = VCS.setup(%{repo: repo, adapter: GitAdapter})

      context = %FlowStone.Context{
        asset: :integration_test,
        partition: :default,
        run_id: "integration-clean-#{:rand.uniform(1_000_000)}",
        resources: %{git: vcs_state},
        metadata: %{},
        started_at: DateTime.utc_now()
      }

      # Repo is already clean (initial commit only)
      assert {:ok, result} =
               Git.run(
                 %{operation: :commit, message: "Should not commit"},
                 context
               )

      assert %{status: :no_changes} = result
    end

    test "diff between refs through step", %{repo: repo} do
      {:ok, vcs_state} = VCS.setup(%{repo: repo, adapter: GitAdapter})

      # Create a second commit
      File.write!(Path.join(repo, "second.txt"), "Second file\n")
      System.cmd("git", ["add", "second.txt"], cd: repo)
      System.cmd("git", ["commit", "-m", "Second commit"], cd: repo)

      context = %FlowStone.Context{
        asset: :integration_test,
        partition: :default,
        run_id: "integration-diff-#{:rand.uniform(1_000_000)}",
        resources: %{git: vcs_state},
        metadata: %{},
        started_at: DateTime.utc_now()
      }

      assert {:ok, diff_result} =
               Git.run(
                 %{operation: :diff, from: "HEAD~1", to: "HEAD"},
                 context
               )

      assert is_binary(diff_result.patch)
      assert diff_result.patch =~ "second.txt"
      assert diff_result.stats.files_changed == 1
    end

    test "telemetry events emitted during workflow", %{repo: repo} do
      test_pid = self()

      handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end

      handler_id = "integration-telemetry-#{:erlang.unique_integer([:positive])}"

      :telemetry.attach_many(
        handler_id,
        [
          [:portfolio, :vcs, :status, :start],
          [:portfolio, :vcs, :status, :stop],
          [:portfolio, :vcs, :commit, :start],
          [:portfolio, :vcs, :commit, :stop],
          [:portfolio, :vcs, :diff, :start],
          [:portfolio, :vcs, :diff, :stop]
        ],
        handler,
        nil
      )

      {:ok, vcs_state} = VCS.setup(%{repo: repo, adapter: GitAdapter})

      context = %FlowStone.Context{
        asset: :integration_test,
        partition: :default,
        run_id: "integration-telemetry-#{:rand.uniform(1_000_000)}",
        resources: %{git: vcs_state},
        metadata: %{},
        started_at: DateTime.utc_now()
      }

      # Create file and commit
      File.write!(Path.join(repo, "telemetry_test.txt"), "Telemetry test\n")

      # Run commit step (internally calls status + stage_all + commit)
      {:ok, _} = Git.run(%{operation: :commit, message: "Telemetry commit"}, context)

      # Verify status telemetry was emitted (from the commit step's status check)
      assert_received {:telemetry, [:portfolio, :vcs, :status, :start], _, _}
      assert_received {:telemetry, [:portfolio, :vcs, :status, :stop], _, _}

      # Verify commit telemetry was emitted
      assert_received {:telemetry, [:portfolio, :vcs, :commit, :start], _, _}
      assert_received {:telemetry, [:portfolio, :vcs, :commit, :stop], measurements, _}
      assert is_integer(measurements.duration)

      :telemetry.detach(handler_id)
    end
  end
end
