defmodule Command.FlowStone.Resources.ProgressTrackerTest do
  use Command.DataCase, async: true

  alias Command.FlowStone.Resources.ProgressTracker

  describe "setup/1" do
    test "returns {:ok, progress_state} with run_id" do
      run_id = Ecto.UUID.generate()
      config = %{run_id: run_id}

      assert {:ok, progress} = ProgressTracker.setup(config)
      assert progress.run_id == run_id
    end

    test "returns {:error, reason} when run_id missing" do
      config = %{}

      assert {:error, reason} = ProgressTracker.setup(config)
      assert reason == :run_id_required
    end

    test "returns {:error, reason} when run_id is nil" do
      config = %{run_id: nil}

      assert {:error, reason} = ProgressTracker.setup(config)
      assert reason == :run_id_required
    end
  end

  describe "mark_run_started/1" do
    setup do
      run_id = Ecto.UUID.generate()
      {:ok, progress} = ProgressTracker.setup(%{run_id: run_id})
      %{progress: progress, run_id: run_id}
    end

    test "updates prompt_set_runs status to running", %{progress: progress, run_id: run_id} do
      # Create a prompt_set_run record (mocked for now since we don't have the schema yet)
      # This test assumes the schema exists
      assert :ok = ProgressTracker.mark_run_started(progress)

      # Verification would query the database
      # For now, we're testing the function returns :ok
    end
  end

  describe "mark_run_completed/1" do
    setup do
      run_id = Ecto.UUID.generate()
      {:ok, progress} = ProgressTracker.setup(%{run_id: run_id})
      %{progress: progress, run_id: run_id}
    end

    test "updates prompt_set_runs status to completed", %{progress: progress} do
      assert :ok = ProgressTracker.mark_run_completed(progress)
    end
  end

  describe "mark_step_started/2" do
    setup do
      run_id = Ecto.UUID.generate()
      {:ok, progress} = ProgressTracker.setup(%{run_id: run_id})
      step_id = Ecto.UUID.generate()
      %{progress: progress, run_id: run_id, step_id: step_id}
    end

    test "updates prompt_step_runs status to running", %{progress: progress, step_id: step_id} do
      assert :ok = ProgressTracker.mark_step_started(progress, step_id)
    end
  end

  describe "mark_step_terminal/3" do
    setup do
      run_id = Ecto.UUID.generate()
      {:ok, progress} = ProgressTracker.setup(%{run_id: run_id})
      step_id = Ecto.UUID.generate()
      %{progress: progress, run_id: run_id, step_id: step_id}
    end

    test "updates prompt_step_runs terminal status to completed", %{
      progress: progress,
      step_id: step_id
    } do
      status = "completed"
      attrs = %{completed_at: DateTime.utc_now()}

      assert :ok = ProgressTracker.mark_step_terminal(progress, step_id, status, attrs)
    end

    test "updates prompt_step_runs terminal status to failed", %{
      progress: progress,
      step_id: step_id
    } do
      status = "failed"
      attrs = %{error: "Test error"}

      assert :ok = ProgressTracker.mark_step_terminal(progress, step_id, status, attrs)
    end

    test "accepts empty attrs", %{progress: progress, step_id: step_id} do
      status = "completed"

      assert :ok = ProgressTracker.mark_step_terminal(progress, step_id, status)
    end
  end

  describe "mark_repo_terminal/4" do
    setup do
      run_id = Ecto.UUID.generate()
      {:ok, progress} = ProgressTracker.setup(%{run_id: run_id})
      step_id = Ecto.UUID.generate()
      %{progress: progress, run_id: run_id, step_id: step_id}
    end

    test "updates prompt_repo_results status and commit_status", %{
      progress: progress,
      step_id: step_id
    } do
      repo_name = "command"

      attrs = %{
        status: "completed",
        commit_status: "committed",
        commit_hash: "abc123"
      }

      assert :ok = ProgressTracker.mark_repo_terminal(progress, step_id, repo_name, attrs)
    end

    test "handles failed repo with error", %{progress: progress, step_id: step_id} do
      repo_name = "flowstone"

      attrs = %{
        status: "failed",
        commit_status: "failed",
        error: "Commit failed"
      }

      assert :ok = ProgressTracker.mark_repo_terminal(progress, step_id, repo_name, attrs)
    end

    test "accepts empty attrs map", %{progress: progress, step_id: step_id} do
      repo_name = "command"

      assert :ok = ProgressTracker.mark_repo_terminal(progress, step_id, repo_name, %{})
    end
  end

  describe "teardown/1" do
    test "returns :ok" do
      run_id = Ecto.UUID.generate()
      {:ok, progress} = ProgressTracker.setup(%{run_id: run_id})

      assert :ok = ProgressTracker.teardown(progress)
    end
  end

  describe "health_check/1" do
    test "returns :healthy" do
      run_id = Ecto.UUID.generate()
      {:ok, progress} = ProgressTracker.setup(%{run_id: run_id})

      assert :healthy = ProgressTracker.health_check(progress)
    end
  end
end
