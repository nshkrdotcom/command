defmodule Command.PromptSets.PromptChangesetTest do
  use Command.DataCase, async: true

  alias Command.PromptSets.PromptChangeset

  describe "changeset/2 - prompt scope" do
    test "valid changeset with scope='prompt' requires prompt_step_run_id" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)

      attrs = %{
        scope: "prompt",
        prompt_step_run_id: step.id,
        prompt_set_run_id: run.id
      }

      changeset = PromptChangeset.changeset(%PromptChangeset{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :scope) == "prompt"
      assert get_change(changeset, :prompt_step_run_id) == step.id
    end

    test "valid changeset with all prompt scope fields" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)

      # Create a parent run-scoped changeset for hierarchy
      {:ok, parent_changeset} =
        %PromptChangeset{}
        |> PromptChangeset.changeset(%{
          scope: "run",
          prompt_set_run_id: run.id
        })
        |> Repo.insert()

      attrs = %{
        scope: "prompt",
        prompt_step_run_id: step.id,
        prompt_set_run_id: run.id,
        parent_changeset_id: parent_changeset.id,
        name: "Step 01 Changes",
        description: "Changes from prompt 01",
        status: "in_progress",
        repos_total: 3,
        repos_completed: 1,
        repos_failed: 0,
        branch_name: "feature/prompt-01"
      }

      changeset = PromptChangeset.changeset(%PromptChangeset{}, attrs)

      assert changeset.valid?
    end

    test "prompt scope changeset can have parent_changeset_id" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)

      {:ok, parent} =
        %PromptChangeset{}
        |> PromptChangeset.changeset(%{scope: "run", prompt_set_run_id: run.id})
        |> Repo.insert()

      {:ok, child} =
        %PromptChangeset{}
        |> PromptChangeset.changeset(%{
          scope: "prompt",
          prompt_step_run_id: step.id,
          prompt_set_run_id: run.id,
          parent_changeset_id: parent.id
        })
        |> Repo.insert()

      loaded = Repo.preload(child, :parent_changeset)
      assert loaded.parent_changeset.id == parent.id
    end
  end

  describe "changeset/2 - run scope" do
    test "valid changeset with scope='run' requires prompt_set_run_id and no step id" do
      run = insert(:prompt_set_run)

      attrs = %{
        scope: "run",
        prompt_set_run_id: run.id
      }

      changeset = PromptChangeset.changeset(%PromptChangeset{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :scope) == "run"
      assert get_change(changeset, :prompt_set_run_id) == run.id
    end

    test "run scope cannot have prompt_step_run_id" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)

      attrs = %{
        scope: "run",
        prompt_set_run_id: run.id,
        prompt_step_run_id: step.id
      }

      changeset = PromptChangeset.changeset(%PromptChangeset{}, attrs)

      # The changeset validation should fail based on scope-FK invariant
      refute changeset.valid?
      assert errors_on(changeset)[:prompt_step_run_id]
    end
  end

  describe "changeset/2 - scope validation" do
    test "scope validation - accepts valid scopes" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)

      # Test prompt scope
      changeset =
        PromptChangeset.changeset(%PromptChangeset{}, %{
          scope: "prompt",
          prompt_step_run_id: step.id,
          prompt_set_run_id: run.id
        })

      assert changeset.valid?

      # Test run scope
      changeset =
        PromptChangeset.changeset(%PromptChangeset{}, %{
          scope: "run",
          prompt_set_run_id: run.id
        })

      assert changeset.valid?

      # Test workspace scope
      changeset =
        PromptChangeset.changeset(%PromptChangeset{}, %{
          scope: "workspace"
        })

      assert changeset.valid?
    end

    test "scope validation - rejects invalid scope" do
      run = insert(:prompt_set_run)

      changeset =
        PromptChangeset.changeset(%PromptChangeset{}, %{
          scope: "invalid_scope",
          prompt_set_run_id: run.id
        })

      refute changeset.valid?
      assert %{scope: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "changeset/2 - status validation" do
    test "status validation - accepts valid changeset statuses" do
      run = insert(:prompt_set_run)

      valid_statuses = [
        "pending",
        "in_progress",
        "completed",
        "partial_success",
        "failed",
        "rolled_back"
      ]

      for status <- valid_statuses do
        changeset =
          PromptChangeset.changeset(%PromptChangeset{}, %{
            scope: "run",
            prompt_set_run_id: run.id,
            status: status
          })

        assert changeset.valid?, "Expected status '#{status}' to be valid"
      end
    end

    test "status validation - rejects invalid status" do
      run = insert(:prompt_set_run)

      changeset =
        PromptChangeset.changeset(%PromptChangeset{}, %{
          scope: "run",
          prompt_set_run_id: run.id,
          status: "invalid_status"
        })

      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "cardinality constraints" do
    test "unique index enforces one changeset per run (run scope)" do
      run = insert(:prompt_set_run)

      {:ok, _first} =
        %PromptChangeset{}
        |> PromptChangeset.changeset(%{scope: "run", prompt_set_run_id: run.id})
        |> Repo.insert()

      {:error, changeset} =
        %PromptChangeset{}
        |> PromptChangeset.changeset(%{scope: "run", prompt_set_run_id: run.id})
        |> Repo.insert()

      # The unique index should trigger a constraint error
      assert errors_on(changeset)[:prompt_set_run_id]
    end

    test "unique index enforces one changeset per step (prompt scope)" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)

      {:ok, _first} =
        %PromptChangeset{}
        |> PromptChangeset.changeset(%{
          scope: "prompt",
          prompt_step_run_id: step.id,
          prompt_set_run_id: run.id
        })
        |> Repo.insert()

      {:error, changeset} =
        %PromptChangeset{}
        |> PromptChangeset.changeset(%{
          scope: "prompt",
          prompt_step_run_id: step.id,
          prompt_set_run_id: run.id
        })
        |> Repo.insert()

      assert errors_on(changeset)[:prompt_step_run_id]
    end
  end

  describe "default values" do
    test "default scope is prompt" do
      changeset_struct = %PromptChangeset{}
      assert changeset_struct.scope == "prompt"
    end

    test "default status is pending" do
      changeset_struct = %PromptChangeset{}
      assert changeset_struct.status == "pending"
    end

    test "default counter values are 0" do
      changeset_struct = %PromptChangeset{}
      assert changeset_struct.repos_total == 0
      assert changeset_struct.repos_completed == 0
      assert changeset_struct.repos_failed == 0
    end

    test "pr_urls defaults to empty list" do
      changeset_struct = %PromptChangeset{}
      assert changeset_struct.pr_urls == []
    end
  end

  describe "associations" do
    test "belongs_to prompt_set_run" do
      run = insert(:prompt_set_run)

      {:ok, changeset} =
        %PromptChangeset{}
        |> PromptChangeset.changeset(%{scope: "run", prompt_set_run_id: run.id})
        |> Repo.insert()

      loaded = Repo.preload(changeset, :prompt_set_run)
      assert loaded.prompt_set_run.id == run.id
    end

    test "belongs_to prompt_step_run" do
      run = insert(:prompt_set_run)
      step = insert(:prompt_step_run, prompt_set_run: run)

      {:ok, changeset} =
        %PromptChangeset{}
        |> PromptChangeset.changeset(%{
          scope: "prompt",
          prompt_step_run_id: step.id,
          prompt_set_run_id: run.id
        })
        |> Repo.insert()

      loaded = Repo.preload(changeset, :prompt_step_run)
      assert loaded.prompt_step_run.id == step.id
    end

    test "belongs_to parent_changeset" do
      run = insert(:prompt_set_run)

      {:ok, parent} =
        %PromptChangeset{}
        |> PromptChangeset.changeset(%{scope: "run", prompt_set_run_id: run.id})
        |> Repo.insert()

      step = insert(:prompt_step_run, prompt_set_run: run)

      {:ok, child} =
        %PromptChangeset{}
        |> PromptChangeset.changeset(%{
          scope: "prompt",
          prompt_step_run_id: step.id,
          prompt_set_run_id: run.id,
          parent_changeset_id: parent.id
        })
        |> Repo.insert()

      loaded = Repo.preload(child, :parent_changeset)
      assert loaded.parent_changeset.id == parent.id
    end
  end
end
