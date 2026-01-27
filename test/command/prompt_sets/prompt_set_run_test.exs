defmodule Command.PromptSets.PromptSetRunTest do
  use Command.DataCase, async: true

  alias Command.PromptSets.PromptSetRun

  describe "changeset/2" do
    test "valid changeset with required fields" do
      prompt_set = insert(:prompt_set)
      attrs = %{prompt_set_id: prompt_set.id}

      changeset = PromptSetRun.changeset(%PromptSetRun{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :prompt_set_id) == prompt_set.id
    end

    test "valid changeset with all fields" do
      prompt_set = insert(:prompt_set)

      attrs = %{
        prompt_set_id: prompt_set.id,
        status: "running",
        current_prompt: "02",
        last_completed_prompt: "01",
        branch_name: "feature/prompt-set-123",
        branch_strategy: "feature_branch",
        config_snapshot: %{"project_dir" => "/path"},
        started_at: DateTime.utc_now(),
        total_prompts: 5,
        completed_prompts: 1,
        failed_prompts: 0,
        total_input_tokens: 1000,
        total_output_tokens: 500,
        total_cost_usd: Decimal.new("0.05")
      }

      changeset = PromptSetRun.changeset(%PromptSetRun{}, attrs)

      assert changeset.valid?
    end

    test "invalid changeset missing prompt_set_id" do
      changeset = PromptSetRun.changeset(%PromptSetRun{}, %{})

      refute changeset.valid?
      assert %{prompt_set_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "status validation - accepts valid run states" do
      prompt_set = insert(:prompt_set)

      valid_statuses = [
        "pending",
        "running",
        "paused",
        "completed",
        "partial_success",
        "failed",
        "aborted"
      ]

      for status <- valid_statuses do
        changeset =
          PromptSetRun.changeset(%PromptSetRun{}, %{
            prompt_set_id: prompt_set.id,
            status: status
          })

        assert changeset.valid?, "Expected status '#{status}' to be valid"
      end
    end

    test "status validation - rejects invalid status" do
      prompt_set = insert(:prompt_set)

      changeset =
        PromptSetRun.changeset(%PromptSetRun{}, %{
          prompt_set_id: prompt_set.id,
          status: "invalid_status"
        })

      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "default values for aggregate metrics" do
      run = %PromptSetRun{}

      assert run.total_prompts == 0
      assert run.completed_prompts == 0
      assert run.failed_prompts == 0
      assert run.total_input_tokens == 0
      assert run.total_output_tokens == 0
      assert Decimal.equal?(run.total_cost_usd, Decimal.new(0))
    end

    test "default status is pending" do
      run = %PromptSetRun{}
      assert run.status == "pending"
    end

    test "config_snapshot defaults to empty map" do
      run = %PromptSetRun{}
      assert run.config_snapshot == %{}
    end
  end

  describe "foreign key constraint" do
    test "enforces foreign key to prompt_sets" do
      fake_id = Ecto.UUID.generate()

      {:error, changeset} =
        %PromptSetRun{}
        |> PromptSetRun.changeset(%{prompt_set_id: fake_id})
        |> Repo.insert()

      assert %{prompt_set_id: ["does not exist"]} = errors_on(changeset)
    end
  end

  describe "associations" do
    test "belongs_to prompt_set association" do
      prompt_set = insert(:prompt_set)
      run = insert(:prompt_set_run, prompt_set: prompt_set)

      loaded = Repo.preload(run, :prompt_set)
      assert loaded.prompt_set.id == prompt_set.id
    end

    test "has_many step_runs association" do
      run = insert(:prompt_set_run)
      step1 = insert(:prompt_step_run, prompt_set_run: run, prompt_num: "01")
      step2 = insert(:prompt_step_run, prompt_set_run: run, prompt_num: "02")

      loaded = Repo.preload(run, :step_runs)
      assert length(loaded.step_runs) == 2
      step_ids = Enum.map(loaded.step_runs, & &1.id)
      assert step1.id in step_ids
      assert step2.id in step_ids
    end

    test "optional pipeline_run association" do
      run = insert(:prompt_set_run, pipeline_run: nil)
      assert run.pipeline_run_id == nil

      loaded = Repo.preload(run, :pipeline_run)
      assert loaded.pipeline_run == nil
    end
  end
end
