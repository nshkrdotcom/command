defmodule Command.PromptSets.PromptStepRunTest do
  use Command.DataCase, async: true

  alias Command.PromptSets.PromptStepRun

  describe "changeset/2" do
    test "valid changeset with required fields" do
      run = insert(:prompt_set_run)
      attrs = %{prompt_set_run_id: run.id, prompt_num: "01"}

      changeset = PromptStepRun.changeset(%PromptStepRun{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :prompt_set_run_id) == run.id
      assert get_change(changeset, :prompt_num) == "01"
    end

    test "valid changeset with all fields" do
      run = insert(:prompt_set_run)

      attrs = %{
        prompt_set_run_id: run.id,
        prompt_num: "02",
        status: "completed",
        provider: "claude",
        model: "claude-sonnet-4-20250514",
        commit_hash: "abc123def456789012345678901234567890abcd",
        commit_status: "committed",
        target_repo: "command",
        commit_hashes: [
          %{"repo" => "command", "hash" => "abc123", "status" => "committed"}
        ],
        input_tokens: 1500,
        output_tokens: 800,
        cost_usd: Decimal.new("0.025"),
        duration_ms: 5000,
        log_artifact_id: Ecto.UUID.generate(),
        events_artifact_id: Ecto.UUID.generate(),
        started_at: DateTime.utc_now() |> DateTime.add(-5, :second),
        completed_at: DateTime.utc_now()
      }

      changeset = PromptStepRun.changeset(%PromptStepRun{}, attrs)

      assert changeset.valid?
    end

    test "invalid changeset missing required fields" do
      changeset = PromptStepRun.changeset(%PromptStepRun{}, %{})

      refute changeset.valid?

      errors = errors_on(changeset)
      assert errors[:prompt_set_run_id] == ["can't be blank"]
      assert errors[:prompt_num] == ["can't be blank"]
    end

    test "invalid changeset missing prompt_set_run_id" do
      changeset = PromptStepRun.changeset(%PromptStepRun{}, %{prompt_num: "01"})

      refute changeset.valid?
      assert %{prompt_set_run_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid changeset missing prompt_num" do
      run = insert(:prompt_set_run)
      changeset = PromptStepRun.changeset(%PromptStepRun{}, %{prompt_set_run_id: run.id})

      refute changeset.valid?
      assert %{prompt_num: ["can't be blank"]} = errors_on(changeset)
    end

    test "status validation - accepts valid step states" do
      run = insert(:prompt_set_run)

      valid_statuses = ["pending", "running", "completed", "partial_success", "failed", "skipped"]

      for status <- valid_statuses do
        changeset =
          PromptStepRun.changeset(%PromptStepRun{}, %{
            prompt_set_run_id: run.id,
            prompt_num: "01",
            status: status
          })

        assert changeset.valid?, "Expected status '#{status}' to be valid"
      end
    end

    test "status validation - rejects invalid status" do
      run = insert(:prompt_set_run)

      changeset =
        PromptStepRun.changeset(%PromptStepRun{}, %{
          prompt_set_run_id: run.id,
          prompt_num: "01",
          status: "invalid_status"
        })

      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "commit_status validation - accepts nil" do
      run = insert(:prompt_set_run)

      changeset =
        PromptStepRun.changeset(%PromptStepRun{}, %{
          prompt_set_run_id: run.id,
          prompt_num: "01",
          commit_status: nil
        })

      assert changeset.valid?
    end

    test "commit_status validation - accepts valid commit statuses" do
      run = insert(:prompt_set_run)
      valid_commit_statuses = ["committed", "no_commit", "no_changes", "failed", "skipped"]

      for commit_status <- valid_commit_statuses do
        changeset =
          PromptStepRun.changeset(%PromptStepRun{}, %{
            prompt_set_run_id: run.id,
            prompt_num: "01",
            commit_status: commit_status
          })

        assert changeset.valid?, "Expected commit_status '#{commit_status}' to be valid"
      end
    end

    test "commit_status validation - rejects invalid commit status" do
      run = insert(:prompt_set_run)

      changeset =
        PromptStepRun.changeset(%PromptStepRun{}, %{
          prompt_set_run_id: run.id,
          prompt_num: "01",
          commit_status: "invalid_commit_status"
        })

      refute changeset.valid?
      assert %{commit_status: ["is invalid"]} = errors_on(changeset)
    end

    test "default values for usage metrics" do
      step = %PromptStepRun{}

      assert step.input_tokens == 0
      assert step.output_tokens == 0
      assert Decimal.equal?(step.cost_usd, Decimal.new(0))
      assert step.retry_count == 0
    end

    test "default status is pending" do
      step = %PromptStepRun{}
      assert step.status == "pending"
    end

    test "commit_hashes defaults to empty list" do
      step = %PromptStepRun{}
      assert step.commit_hashes == []
    end
  end

  describe "unique constraint" do
    test "enforces unique (prompt_set_run_id, prompt_num)" do
      run = insert(:prompt_set_run)
      _step1 = insert(:prompt_step_run, prompt_set_run: run, prompt_num: "01")

      {:error, changeset} =
        %PromptStepRun{}
        |> PromptStepRun.changeset(%{prompt_set_run_id: run.id, prompt_num: "01"})
        |> Repo.insert()

      assert %{prompt_num: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same prompt_num for different runs" do
      run1 = insert(:prompt_set_run)
      run2 = insert(:prompt_set_run)

      {:ok, _step1} =
        %PromptStepRun{}
        |> PromptStepRun.changeset(%{prompt_set_run_id: run1.id, prompt_num: "01"})
        |> Repo.insert()

      {:ok, step2} =
        %PromptStepRun{}
        |> PromptStepRun.changeset(%{prompt_set_run_id: run2.id, prompt_num: "01"})
        |> Repo.insert()

      assert step2.prompt_num == "01"
    end
  end

  describe "associations" do
    test "belongs_to prompt_set_run association" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)

      loaded = Repo.preload(step, :prompt_set_run)
      assert loaded.prompt_set_run.id == run.id
    end
  end
end
