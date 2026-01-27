defmodule Command.PromptSetsTest do
  use Command.DataCase, async: false

  alias Command.PromptSets

  alias Command.PromptSets.{
    PromptSet,
    PromptSetRun,
    PromptStepRun,
    PromptChangeset,
    PromptRepoResult
  }

  # ============================================================================
  # PromptSet CRUD Tests
  # ============================================================================

  describe "create_prompt_set/1" do
    test "with valid attrs creates a prompt set" do
      attrs = %{
        name: "Test Prompt Set",
        slug: "test-prompt-set",
        prompts: [%{"num" => "01", "name" => "First Prompt"}],
        config: %{"project_dir" => "/path/to/project"}
      }

      assert {:ok, %PromptSet{} = prompt_set} = PromptSets.create_prompt_set(attrs)
      assert prompt_set.name == "Test Prompt Set"
      assert prompt_set.slug == "test-prompt-set"
      assert prompt_set.status == "active"
      assert length(prompt_set.prompts) == 1
    end

    test "with invalid attrs returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = PromptSets.create_prompt_set(%{})
    end

    test "with duplicate slug returns error" do
      attrs = %{name: "Test", slug: "duplicate-slug"}
      {:ok, _} = PromptSets.create_prompt_set(attrs)

      assert {:error, changeset} =
               PromptSets.create_prompt_set(%{name: "Another", slug: "duplicate-slug"})

      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "get_prompt_set/1" do
    test "returns prompt set when found" do
      prompt_set = insert(:prompt_set)
      assert %PromptSet{} = PromptSets.get_prompt_set(prompt_set.id)
    end

    test "returns nil when not found" do
      assert PromptSets.get_prompt_set(Ecto.UUID.generate()) == nil
    end
  end

  describe "get_prompt_set!/1" do
    test "returns prompt set when found" do
      prompt_set = insert(:prompt_set)
      assert %PromptSet{} = PromptSets.get_prompt_set!(prompt_set.id)
    end

    test "raises when not found" do
      assert_raise Ecto.NoResultsError, fn ->
        PromptSets.get_prompt_set!(Ecto.UUID.generate())
      end
    end
  end

  describe "get_prompt_set_by_slug/1" do
    test "returns prompt set when found" do
      prompt_set = insert(:prompt_set, slug: "my-slug")
      found = PromptSets.get_prompt_set_by_slug("my-slug")

      assert found.id == prompt_set.id
    end

    test "returns nil when not found" do
      assert PromptSets.get_prompt_set_by_slug("nonexistent") == nil
    end
  end

  describe "list_prompt_sets/0" do
    test "returns all active prompt sets" do
      _active1 = insert(:prompt_set, status: "active")
      _active2 = insert(:prompt_set, status: "active")
      _archived = insert(:prompt_set, status: "archived")

      result = PromptSets.list_prompt_sets()

      assert length(result) == 2
      assert Enum.all?(result, &(&1.status == "active"))
    end
  end

  describe "list_prompt_sets/1 with filters" do
    test "filters by status" do
      _active = insert(:prompt_set, status: "active")
      archived = insert(:prompt_set, status: "archived")
      _draft = insert(:prompt_set, status: "draft")

      result = PromptSets.list_prompt_sets(status: "archived")

      assert length(result) == 1
      assert hd(result).id == archived.id
    end

    test "filters by doc_set_id" do
      ps1 = insert(:prompt_set, doc_set_id: "doc-123")
      _ps2 = insert(:prompt_set, doc_set_id: "doc-456")

      result = PromptSets.list_prompt_sets(doc_set_id: "doc-123")

      assert length(result) == 1
      assert hd(result).id == ps1.id
    end

    test "returns all with empty filters" do
      insert(:prompt_set, status: "active")
      insert(:prompt_set, status: "active")

      result = PromptSets.list_prompt_sets([])

      assert length(result) == 2
    end
  end

  describe "update_prompt_set/2" do
    test "with valid attrs updates the prompt set" do
      prompt_set = insert(:prompt_set, name: "Old Name")

      assert {:ok, updated} = PromptSets.update_prompt_set(prompt_set, %{name: "New Name"})
      assert updated.name == "New Name"
    end

    test "with invalid attrs returns error changeset" do
      prompt_set = insert(:prompt_set)

      assert {:error, %Ecto.Changeset{}} =
               PromptSets.update_prompt_set(prompt_set, %{status: "invalid"})
    end
  end

  describe "delete_prompt_set/1" do
    test "soft deletes by archiving the prompt set" do
      prompt_set = insert(:prompt_set, status: "active")

      assert {:ok, deleted} = PromptSets.delete_prompt_set(prompt_set)
      assert deleted.status == "archived"
    end
  end

  describe "change_prompt_set/1" do
    test "returns a changeset" do
      prompt_set = insert(:prompt_set)
      assert %Ecto.Changeset{} = PromptSets.change_prompt_set(prompt_set)
    end

    test "returns a changeset with attrs" do
      prompt_set = insert(:prompt_set)
      changeset = PromptSets.change_prompt_set(prompt_set, %{name: "Changed"})

      assert %Ecto.Changeset{} = changeset
      assert get_change(changeset, :name) == "Changed"
    end
  end

  # ============================================================================
  # PromptSetRun Tests
  # ============================================================================

  describe "create_run/2" do
    test "creates run with config snapshot" do
      prompt_set =
        insert(:prompt_set,
          prompts: [
            %{"num" => "01", "name" => "First"},
            %{"num" => "02", "name" => "Second"}
          ],
          config: %{"project_dir" => "/path"}
        )

      assert {:ok, %PromptSetRun{} = run} = PromptSets.create_run(prompt_set)
      assert run.prompt_set_id == prompt_set.id
      assert run.status == "pending"
      assert run.config_snapshot["project_dir"] == "/path"
      assert run.total_prompts == 2
    end

    test "initializes step_runs for all prompts" do
      prompt_set =
        insert(:prompt_set,
          prompts: [
            %{"num" => "01", "name" => "First"},
            %{"num" => "02", "name" => "Second"},
            %{"num" => "03", "name" => "Third"}
          ]
        )

      {:ok, run} = PromptSets.create_run(prompt_set)
      run = Repo.preload(run, :step_runs)

      assert length(run.step_runs) == 3

      nums = Enum.map(run.step_runs, & &1.prompt_num) |> Enum.sort()
      assert nums == ["01", "02", "03"]

      assert Enum.all?(run.step_runs, &(&1.status == "pending"))
    end

    test "accepts optional pipeline_run_id" do
      prompt_set = insert(:prompt_set)
      # Note: We can't easily test with a real pipeline_run without the table,
      # so we test that the attribute is accepted (it will be nil if not provided)

      {:ok, run} = PromptSets.create_run(prompt_set, [])
      assert run.pipeline_run_id == nil
    end
  end

  describe "get_run/1" do
    test "returns run with preloads" do
      prompt_set = insert(:prompt_set, prompts: [%{"num" => "01", "name" => "First"}])
      {:ok, created_run} = PromptSets.create_run(prompt_set)

      run = PromptSets.get_run(created_run.id)

      assert run.id == created_run.id
      assert Ecto.assoc_loaded?(run.prompt_set)
      assert Ecto.assoc_loaded?(run.step_runs)
    end

    test "returns nil when not found" do
      assert PromptSets.get_run(Ecto.UUID.generate()) == nil
    end
  end

  describe "list_runs_for_prompt_set/1" do
    test "returns runs for a specific prompt set" do
      ps1 = insert(:prompt_set)
      ps2 = insert(:prompt_set)

      {:ok, run1} = PromptSets.create_run(ps1)
      {:ok, run2} = PromptSets.create_run(ps1)
      {:ok, _run3} = PromptSets.create_run(ps2)

      runs = PromptSets.list_runs_for_prompt_set(ps1.id)

      assert length(runs) == 2
      run_ids = Enum.map(runs, & &1.id)
      assert run1.id in run_ids
      assert run2.id in run_ids
    end
  end

  describe "list_active_runs/0" do
    test "returns pending, running, and paused runs" do
      ps = insert(:prompt_set)

      {:ok, pending_run} = PromptSets.create_run(ps)
      {:ok, running_run} = PromptSets.create_run(ps)
      {:ok, _} = PromptSets.start_run(running_run)
      {:ok, paused_run} = PromptSets.create_run(ps)
      {:ok, started} = PromptSets.start_run(paused_run)
      {:ok, _} = PromptSets.pause_run(started)
      {:ok, completed_run} = PromptSets.create_run(ps)
      {:ok, started2} = PromptSets.start_run(completed_run)
      {:ok, _} = PromptSets.complete_run(started2)

      runs = PromptSets.list_active_runs()
      statuses = Enum.map(runs, & &1.status)

      assert "pending" in statuses
      assert "running" in statuses
      assert "paused" in statuses
      refute "completed" in statuses
    end
  end

  # ============================================================================
  # PromptStepRun Tests
  # ============================================================================

  describe "get_step_run/2" do
    test "returns step by run_id and prompt_num" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}, %{"num" => "02"}])
      {:ok, run} = PromptSets.create_run(ps)

      step = PromptSets.get_step_run(run.id, "02")

      assert step.prompt_num == "02"
      assert step.prompt_set_run_id == run.id
    end

    test "returns nil when not found" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)

      assert PromptSets.get_step_run(run.id, "99") == nil
    end
  end

  describe "update_step_status/3" do
    test "updates step status" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      step = PromptSets.get_step_run(run.id, "01")

      {:ok, updated} = PromptSets.update_step_status(step, "running", %{})

      assert updated.status == "running"
    end

    test "updates step with additional attributes" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      step = PromptSets.get_step_run(run.id, "01")

      {:ok, updated} =
        PromptSets.update_step_status(step, "running", %{
          started_at: DateTime.utc_now(),
          provider: "claude",
          model: "claude-sonnet-4-20250514"
        })

      assert updated.status == "running"
      assert updated.provider == "claude"
      assert updated.model == "claude-sonnet-4-20250514"
    end
  end

  # ============================================================================
  # PromptChangeset Tests
  # ============================================================================

  describe "create_prompt_changeset/2" do
    test "creates changeset with scope='prompt' and links to step" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      step = PromptSets.get_step_run(run.id, "01")

      {:ok, changeset} = PromptSets.create_prompt_changeset(step)

      assert changeset.scope == "prompt"
      assert changeset.prompt_step_run_id == step.id
      assert changeset.prompt_set_run_id == run.id
    end

    test "can link to parent run changeset" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      {:ok, run_changeset} = PromptSets.create_run_changeset(run)
      step = PromptSets.get_step_run(run.id, "01")

      {:ok, prompt_changeset} =
        PromptSets.create_prompt_changeset(step, %{parent_changeset_id: run_changeset.id})

      assert prompt_changeset.parent_changeset_id == run_changeset.id
    end
  end

  describe "create_run_changeset/2" do
    test "creates changeset with scope='run' and no step id" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)

      {:ok, changeset} = PromptSets.create_run_changeset(run)

      assert changeset.scope == "run"
      assert changeset.prompt_set_run_id == run.id
      assert changeset.prompt_step_run_id == nil
    end
  end

  describe "update_changeset_status/3" do
    test "updates changeset status" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      {:ok, changeset} = PromptSets.create_run_changeset(run)

      {:ok, updated} = PromptSets.update_changeset_status(changeset, "in_progress")

      assert updated.status == "in_progress"
    end

    test "enforces valid status transitions" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      {:ok, changeset} = PromptSets.create_run_changeset(run)

      # pending -> completed (should work)
      {:ok, completed} = PromptSets.update_changeset_status(changeset, "completed")
      assert completed.status == "completed"
    end
  end

  # ============================================================================
  # PromptRepoResult Tests
  # ============================================================================

  describe "upsert_repo_result/3" do
    test "creates new repo result" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      step = PromptSets.get_step_run(run.id, "01")

      {:ok, result} =
        PromptSets.upsert_repo_result(step, "command", %{
          status: "pending",
          repo_path: "/path/to/command"
        })

      assert result.repo_name == "command"
      assert result.prompt_step_run_id == step.id
    end

    test "updates existing repo result" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      step = PromptSets.get_step_run(run.id, "01")

      {:ok, _} = PromptSets.upsert_repo_result(step, "command", %{status: "pending"})
      now = DateTime.utc_now()

      {:ok, updated} =
        PromptSets.upsert_repo_result(step, "command", %{
          status: "completed",
          commit_status: "committed",
          commit_hash: "abc123def456789012345678901234567890abcd",
          started_at: now |> DateTime.add(-5, :second),
          completed_at: now
        })

      assert updated.status == "completed"
      assert updated.commit_status == "committed"
    end

    test "enforces status/commit_status invariants" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      step = PromptSets.get_step_run(run.id, "01")

      # completed status requires commit_status
      {:error, changeset} =
        PromptSets.upsert_repo_result(step, "command", %{
          status: "completed",
          commit_status: nil,
          started_at: DateTime.utc_now() |> DateTime.add(-5, :second),
          completed_at: DateTime.utc_now()
        })

      assert errors_on(changeset)[:commit_status]
    end
  end

  describe "list_repo_results/1" do
    test "returns ordered repo results for step" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      step = PromptSets.get_step_run(run.id, "01")

      {:ok, _} = PromptSets.upsert_repo_result(step, "zebra-repo", %{})
      {:ok, _} = PromptSets.upsert_repo_result(step, "alpha-repo", %{})
      {:ok, _} = PromptSets.upsert_repo_result(step, "middle-repo", %{})

      results = PromptSets.list_repo_results(step.id)

      assert length(results) == 3
      names = Enum.map(results, & &1.repo_name)
      assert names == ["alpha-repo", "middle-repo", "zebra-repo"]
    end
  end

  # ============================================================================
  # Run State Machine Tests
  # ============================================================================

  describe "start_run/1" do
    test "transitions pending -> running" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)

      assert run.status == "pending"

      {:ok, started} = PromptSets.start_run(run)

      assert started.status == "running"
      assert started.started_at != nil
    end

    test "fails if already running" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      {:ok, running} = PromptSets.start_run(run)

      assert {:error, :invalid_transition} = PromptSets.start_run(running)
    end
  end

  describe "pause_run/1" do
    test "transitions running -> paused" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      {:ok, running} = PromptSets.start_run(run)

      {:ok, paused} = PromptSets.pause_run(running)

      assert paused.status == "paused"
    end

    test "fails if not running" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)

      assert {:error, :invalid_transition} = PromptSets.pause_run(run)
    end
  end

  describe "resume_run/1" do
    test "transitions paused -> running" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      {:ok, running} = PromptSets.start_run(run)
      {:ok, paused} = PromptSets.pause_run(running)

      {:ok, resumed} = PromptSets.resume_run(paused)

      assert resumed.status == "running"
    end

    test "transitions partial_success -> running" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      {:ok, running} = PromptSets.start_run(run)

      # Directly set to partial_success for this test
      {:ok, partial} =
        running
        |> Ecto.Changeset.change(%{status: "partial_success"})
        |> Repo.update()

      {:ok, resumed} = PromptSets.resume_run(partial)

      assert resumed.status == "running"
    end
  end

  describe "complete_run/1" do
    test "transitions running -> completed" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      {:ok, running} = PromptSets.start_run(run)

      {:ok, completed} = PromptSets.complete_run(running)

      assert completed.status == "completed"
      assert completed.completed_at != nil
    end
  end

  describe "fail_run/2" do
    test "transitions running -> failed with error" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      {:ok, running} = PromptSets.start_run(run)

      {:ok, failed} = PromptSets.fail_run(running, "Something went wrong")

      assert failed.status == "failed"
      assert failed.error_summary == "Something went wrong"
      assert failed.completed_at != nil
    end
  end

  describe "abort_run/1" do
    test "transitions pending -> aborted" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)

      {:ok, aborted} = PromptSets.abort_run(run)

      assert aborted.status == "aborted"
    end

    test "transitions running -> aborted" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      {:ok, running} = PromptSets.start_run(run)

      {:ok, aborted} = PromptSets.abort_run(running)

      assert aborted.status == "aborted"
    end

    test "transitions paused -> aborted" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      {:ok, running} = PromptSets.start_run(run)
      {:ok, paused} = PromptSets.pause_run(running)

      {:ok, aborted} = PromptSets.abort_run(paused)

      assert aborted.status == "aborted"
    end
  end

  # ============================================================================
  # Step State Machine Tests
  # ============================================================================

  describe "start_step/1" do
    test "transitions pending -> running" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      step = PromptSets.get_step_run(run.id, "01")

      {:ok, started} = PromptSets.start_step(step)

      assert started.status == "running"
      assert started.started_at != nil
    end
  end

  describe "complete_step/3" do
    test "transitions running -> completed with usage" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      step = PromptSets.get_step_run(run.id, "01")
      {:ok, running} = PromptSets.start_step(step)

      usage = %{
        input_tokens: 1000,
        output_tokens: 500,
        cost_usd: Decimal.new("0.015")
      }

      {:ok, completed} = PromptSets.complete_step(running, usage)

      assert completed.status == "completed"
      assert completed.input_tokens == 1000
      assert completed.output_tokens == 500
      assert Decimal.equal?(completed.cost_usd, Decimal.new("0.015"))
      assert completed.completed_at != nil
    end

    test "transitions running -> partial_success" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      step = PromptSets.get_step_run(run.id, "01")
      {:ok, running} = PromptSets.start_step(step)

      usage = %{input_tokens: 500, output_tokens: 250, cost_usd: Decimal.new("0.01")}

      {:ok, partial} = PromptSets.complete_step(running, usage, "partial_success")

      assert partial.status == "partial_success"
    end

    test "updates run aggregate totals atomically" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}, %{"num" => "02"}])
      {:ok, run} = PromptSets.create_run(ps)

      step1 = PromptSets.get_step_run(run.id, "01")
      {:ok, running1} = PromptSets.start_step(step1)

      usage1 = %{input_tokens: 1000, output_tokens: 500, cost_usd: Decimal.new("0.015")}
      {:ok, _} = PromptSets.complete_step(running1, usage1)

      step2 = PromptSets.get_step_run(run.id, "02")
      {:ok, running2} = PromptSets.start_step(step2)

      usage2 = %{input_tokens: 2000, output_tokens: 1000, cost_usd: Decimal.new("0.030")}
      {:ok, _} = PromptSets.complete_step(running2, usage2)

      # Reload run to see aggregates
      updated_run = PromptSets.get_run(run.id)

      assert updated_run.total_input_tokens == 3000
      assert updated_run.total_output_tokens == 1500
      assert Decimal.equal?(updated_run.total_cost_usd, Decimal.new("0.045"))
      assert updated_run.completed_prompts == 2
    end
  end

  describe "fail_step/2" do
    test "transitions running -> failed with error" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      step = PromptSets.get_step_run(run.id, "01")
      {:ok, running} = PromptSets.start_step(step)

      {:ok, failed} =
        PromptSets.fail_step(running, %{
          error_type: "api_error",
          error_message: "Rate limit exceeded"
        })

      assert failed.status == "failed"
      assert failed.error_type == "api_error"
      assert failed.error_message == "Rate limit exceeded"
    end

    test "increments failed_prompts on run" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      step = PromptSets.get_step_run(run.id, "01")
      {:ok, running} = PromptSets.start_step(step)

      {:ok, _} = PromptSets.fail_step(running, %{error_type: "error", error_message: "Failed"})

      updated_run = PromptSets.get_run(run.id)
      assert updated_run.failed_prompts == 1
    end
  end

  describe "skip_step/1" do
    test "transitions pending -> skipped" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)
      step = PromptSets.get_step_run(run.id, "01")

      {:ok, skipped} = PromptSets.skip_step(step)

      assert skipped.status == "skipped"
    end
  end

  # ============================================================================
  # Resume Point Tests
  # ============================================================================

  describe "resume_point/1" do
    test "returns first non-completed step" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}, %{"num" => "02"}, %{"num" => "03"}])
      {:ok, run} = PromptSets.create_run(ps)

      # Complete step 01
      step1 = PromptSets.get_step_run(run.id, "01")
      {:ok, running1} = PromptSets.start_step(step1)
      usage = %{input_tokens: 100, output_tokens: 50, cost_usd: Decimal.new("0.001")}
      {:ok, _} = PromptSets.complete_step(running1, usage)

      resume = PromptSets.resume_point(run.id)

      assert resume.prompt_num == "02"
    end

    test "returns nil when all complete" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)

      step1 = PromptSets.get_step_run(run.id, "01")
      {:ok, running1} = PromptSets.start_step(step1)
      usage = %{input_tokens: 100, output_tokens: 50, cost_usd: Decimal.new("0.001")}
      {:ok, _} = PromptSets.complete_step(running1, usage)

      assert PromptSets.resume_point(run.id) == nil
    end

    test "handles partial_success per policy (default: skip)" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}, %{"num" => "02"}])
      {:ok, run} = PromptSets.create_run(ps)

      # Set step 01 to partial_success
      step1 = PromptSets.get_step_run(run.id, "01")
      {:ok, running1} = PromptSets.start_step(step1)
      usage = %{input_tokens: 100, output_tokens: 50, cost_usd: Decimal.new("0.001")}
      {:ok, _} = PromptSets.complete_step(running1, usage, "partial_success")

      # Default behavior: skip partial_success steps
      resume = PromptSets.resume_point(run.id)

      assert resume.prompt_num == "02"
    end
  end

  # ============================================================================
  # Cost Tracking Tests
  # ============================================================================

  describe "get_run_cost/1" do
    test "returns total_cost_usd" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)

      step = PromptSets.get_step_run(run.id, "01")
      {:ok, running} = PromptSets.start_step(step)
      usage = %{input_tokens: 1000, output_tokens: 500, cost_usd: Decimal.new("0.025")}
      {:ok, _} = PromptSets.complete_step(running, usage)

      cost = PromptSets.get_run_cost(run.id)

      assert Decimal.equal?(cost, Decimal.new("0.025"))
    end

    test "returns zero for runs with no completed steps" do
      ps = insert(:prompt_set, prompts: [%{"num" => "01"}])
      {:ok, run} = PromptSets.create_run(ps)

      cost = PromptSets.get_run_cost(run.id)

      assert Decimal.equal?(cost, Decimal.new(0))
    end
  end
end
