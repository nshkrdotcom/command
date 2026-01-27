defmodule Command.PromptSets.PromptRepoResultTest do
  use Command.DataCase, async: true

  alias Command.PromptSets.PromptRepoResult

  describe "changeset/2 - basic validation" do
    test "valid changeset with prompt_step_run_id and repo_name" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)

      attrs = %{
        prompt_step_run_id: step.id,
        repo_name: "command"
      }

      changeset = PromptRepoResult.changeset(%PromptRepoResult{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :prompt_step_run_id) == step.id
      assert get_change(changeset, :repo_name) == "command"
    end

    test "valid changeset with all fields for completed status" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)

      now = DateTime.utc_now()

      attrs = %{
        prompt_step_run_id: step.id,
        repo_name: "command",
        repo_path: "/home/home/p/g/n/command",
        status: "completed",
        commit_hash: "abc123def456789012345678901234567890abcd",
        commit_status: "committed",
        branch_name: "feature/test",
        pr_url: "https://github.com/org/repo/pull/123",
        files_changed: 5,
        insertions: 100,
        deletions: 50,
        started_at: now |> DateTime.add(-10, :second),
        completed_at: now
      }

      changeset = PromptRepoResult.changeset(%PromptRepoResult{}, attrs)

      assert changeset.valid?
    end

    test "invalid changeset missing required fields" do
      changeset = PromptRepoResult.changeset(%PromptRepoResult{}, %{})

      refute changeset.valid?
      errors = errors_on(changeset)
      assert errors[:prompt_step_run_id] == ["can't be blank"]
      assert errors[:repo_name] == ["can't be blank"]
    end
  end

  describe "changeset/2 - status validation" do
    test "status validation - accepts valid statuses" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)
      valid_statuses = ["pending", "running", "completed", "failed", "skipped"]

      for status <- valid_statuses do
        now = DateTime.utc_now()

        # Build attrs based on status constraints
        attrs =
          case status do
            s when s in ["pending"] ->
              %{
                prompt_step_run_id: step.id,
                repo_name: "repo-#{status}",
                status: status
              }

            "running" ->
              %{
                prompt_step_run_id: step.id,
                repo_name: "repo-#{status}",
                status: status,
                started_at: now
              }

            "completed" ->
              %{
                prompt_step_run_id: step.id,
                repo_name: "repo-#{status}",
                status: status,
                commit_status: "no_changes",
                started_at: now |> DateTime.add(-5, :second),
                completed_at: now
              }

            "failed" ->
              %{
                prompt_step_run_id: step.id,
                repo_name: "repo-#{status}",
                status: status,
                commit_status: "failed",
                error_type: "execution_error",
                error_message: "Test failure",
                started_at: now |> DateTime.add(-5, :second),
                completed_at: now
              }

            "skipped" ->
              %{
                prompt_step_run_id: step.id,
                repo_name: "repo-#{status}",
                status: status,
                commit_status: "skipped",
                started_at: now,
                completed_at: now
              }
          end

        changeset = PromptRepoResult.changeset(%PromptRepoResult{}, attrs)

        assert changeset.valid?,
               "Expected status '#{status}' to be valid, got: #{inspect(errors_on(changeset))}"
      end
    end

    test "status validation - rejects invalid status" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)

      changeset =
        PromptRepoResult.changeset(%PromptRepoResult{}, %{
          prompt_step_run_id: step.id,
          repo_name: "command",
          status: "invalid_status"
        })

      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "changeset/2 - commit_status validation" do
    test "commit_status validation - nil for non-terminal states" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)

      # pending status should have nil commit_status
      changeset =
        PromptRepoResult.changeset(%PromptRepoResult{}, %{
          prompt_step_run_id: step.id,
          repo_name: "command",
          status: "pending",
          commit_status: nil
        })

      assert changeset.valid?
    end

    test "commit_status validation - accepts valid commit statuses" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)

      valid_commit_statuses = ["committed", "no_commit", "no_changes", "failed", "skipped"]

      for commit_status <- valid_commit_statuses do
        now = DateTime.utc_now()

        # Map commit_status to appropriate status
        {status, extra_attrs} =
          case commit_status do
            cs when cs in ["committed", "no_commit", "no_changes"] ->
              {"completed", %{}}

            "failed" ->
              {"failed", %{error_type: "test_error", error_message: "Test"}}

            "skipped" ->
              {"skipped", %{}}
          end

        attrs =
          Map.merge(
            %{
              prompt_step_run_id: step.id,
              repo_name: "repo-#{commit_status}",
              status: status,
              commit_status: commit_status,
              commit_hash:
                if(commit_status == "committed",
                  do: "abc123def456789012345678901234567890abcd",
                  else: nil
                ),
              started_at: now |> DateTime.add(-5, :second),
              completed_at: now
            },
            extra_attrs
          )

        changeset = PromptRepoResult.changeset(%PromptRepoResult{}, attrs)

        assert changeset.valid?,
               "Expected commit_status '#{commit_status}' to be valid, got: #{inspect(errors_on(changeset))}"
      end
    end

    test "commit_status validation - rejects invalid commit_status" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)

      changeset =
        PromptRepoResult.changeset(%PromptRepoResult{}, %{
          prompt_step_run_id: step.id,
          repo_name: "command",
          status: "completed",
          commit_status: "invalid_commit_status"
        })

      refute changeset.valid?
      assert %{commit_status: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "changeset/2 - terminal status requires commit_status" do
    test "terminal status (completed) requires commit_status" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)
      now = DateTime.utc_now()

      changeset =
        PromptRepoResult.changeset(%PromptRepoResult{}, %{
          prompt_step_run_id: step.id,
          repo_name: "command",
          status: "completed",
          commit_status: nil,
          started_at: now |> DateTime.add(-5, :second),
          completed_at: now
        })

      refute changeset.valid?
      assert errors_on(changeset)[:commit_status]
    end

    test "terminal status (failed) requires commit_status" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)
      now = DateTime.utc_now()

      changeset =
        PromptRepoResult.changeset(%PromptRepoResult{}, %{
          prompt_step_run_id: step.id,
          repo_name: "command",
          status: "failed",
          commit_status: nil,
          error_type: "test_error",
          error_message: "Test failure",
          started_at: now |> DateTime.add(-5, :second),
          completed_at: now
        })

      refute changeset.valid?
      assert errors_on(changeset)[:commit_status]
    end
  end

  describe "changeset/2 - status/commit_status alignment" do
    test "completed status with committed commit_status - requires commit_hash" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)
      now = DateTime.utc_now()

      # Without commit_hash - should fail
      changeset =
        PromptRepoResult.changeset(%PromptRepoResult{}, %{
          prompt_step_run_id: step.id,
          repo_name: "command",
          status: "completed",
          commit_status: "committed",
          commit_hash: nil,
          started_at: now |> DateTime.add(-5, :second),
          completed_at: now
        })

      refute changeset.valid?
      assert errors_on(changeset)[:commit_hash]

      # With commit_hash - should succeed
      changeset =
        PromptRepoResult.changeset(%PromptRepoResult{}, %{
          prompt_step_run_id: step.id,
          repo_name: "command",
          status: "completed",
          commit_status: "committed",
          commit_hash: "abc123def456789012345678901234567890abcd",
          started_at: now |> DateTime.add(-5, :second),
          completed_at: now
        })

      assert changeset.valid?
    end

    test "no_changes commit_status requires NULL hash" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)
      now = DateTime.utc_now()

      changeset =
        PromptRepoResult.changeset(%PromptRepoResult{}, %{
          prompt_step_run_id: step.id,
          repo_name: "command",
          status: "completed",
          commit_status: "no_changes",
          commit_hash: "abc123def456789012345678901234567890abcd",
          started_at: now |> DateTime.add(-5, :second),
          completed_at: now
        })

      refute changeset.valid?
      assert errors_on(changeset)[:commit_hash]
    end

    test "no_commit commit_status requires NULL hash" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)
      now = DateTime.utc_now()

      changeset =
        PromptRepoResult.changeset(%PromptRepoResult{}, %{
          prompt_step_run_id: step.id,
          repo_name: "command",
          status: "completed",
          commit_status: "no_commit",
          commit_hash: "abc123def456789012345678901234567890abcd",
          started_at: now |> DateTime.add(-5, :second),
          completed_at: now
        })

      refute changeset.valid?
      assert errors_on(changeset)[:commit_hash]
    end

    test "skipped commit_status requires NULL hash" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)
      now = DateTime.utc_now()

      changeset =
        PromptRepoResult.changeset(%PromptRepoResult{}, %{
          prompt_step_run_id: step.id,
          repo_name: "command",
          status: "skipped",
          commit_status: "skipped",
          commit_hash: "abc123def456789012345678901234567890abcd",
          started_at: now,
          completed_at: now
        })

      refute changeset.valid?
      assert errors_on(changeset)[:commit_hash]
    end
  end

  describe "changeset/2 - failed requires error details" do
    test "failed status requires error_type and error_message" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)
      now = DateTime.utc_now()

      # Missing both error fields
      changeset =
        PromptRepoResult.changeset(%PromptRepoResult{}, %{
          prompt_step_run_id: step.id,
          repo_name: "command",
          status: "failed",
          commit_status: "failed",
          started_at: now |> DateTime.add(-5, :second),
          completed_at: now
        })

      refute changeset.valid?
      errors = errors_on(changeset)
      assert errors[:error_type] || errors[:error_message]

      # With error details - should succeed
      changeset =
        PromptRepoResult.changeset(%PromptRepoResult{}, %{
          prompt_step_run_id: step.id,
          repo_name: "command",
          status: "failed",
          commit_status: "failed",
          error_type: "execution_error",
          error_message: "Process exited with code 1",
          started_at: now |> DateTime.add(-5, :second),
          completed_at: now
        })

      assert changeset.valid?
    end
  end

  describe "unique constraint" do
    test "enforces unique (prompt_step_run_id, repo_name)" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)

      {:ok, _first} =
        %PromptRepoResult{}
        |> PromptRepoResult.changeset(%{
          prompt_step_run_id: step.id,
          repo_name: "command"
        })
        |> Repo.insert()

      {:error, changeset} =
        %PromptRepoResult{}
        |> PromptRepoResult.changeset(%{
          prompt_step_run_id: step.id,
          repo_name: "command"
        })
        |> Repo.insert()

      assert %{repo_name: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same repo_name for different steps" do
      run = insert(:prompt_set_run)
      step1 = insert(:prompt_step_run, prompt_set_run: run, prompt_num: "01")
      step2 = insert(:prompt_step_run, prompt_set_run: run, prompt_num: "02")

      {:ok, _first} =
        %PromptRepoResult{}
        |> PromptRepoResult.changeset(%{
          prompt_step_run_id: step1.id,
          repo_name: "command"
        })
        |> Repo.insert()

      {:ok, second} =
        %PromptRepoResult{}
        |> PromptRepoResult.changeset(%{
          prompt_step_run_id: step2.id,
          repo_name: "command"
        })
        |> Repo.insert()

      assert second.repo_name == "command"
    end
  end

  describe "default values" do
    test "default status is pending" do
      result = %PromptRepoResult{}
      assert result.status == "pending"
    end

    test "default metric values" do
      result = %PromptRepoResult{}
      assert result.files_changed == 0
      assert result.insertions == 0
      assert result.deletions == 0
    end
  end

  describe "associations" do
    test "belongs_to prompt_step_run" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)

      {:ok, result} =
        %PromptRepoResult{}
        |> PromptRepoResult.changeset(%{
          prompt_step_run_id: step.id,
          repo_name: "command"
        })
        |> Repo.insert()

      loaded = Repo.preload(result, :prompt_step_run)
      assert loaded.prompt_step_run.id == step.id
    end

    test "belongs_to prompt_changeset (optional)" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)

      {:ok, changeset} =
        %Command.PromptSets.PromptChangeset{}
        |> Command.PromptSets.PromptChangeset.changeset(%{
          scope: "prompt",
          prompt_step_run_id: step.id,
          prompt_set_run_id: run.id
        })
        |> Repo.insert()

      {:ok, result} =
        %PromptRepoResult{}
        |> PromptRepoResult.changeset(%{
          prompt_step_run_id: step.id,
          repo_name: "command",
          changeset_id: changeset.id
        })
        |> Repo.insert()

      loaded = Repo.preload(result, :prompt_changeset)
      assert loaded.prompt_changeset.id == changeset.id
    end
  end
end
