defmodule Command.PromptSets.WorkspacePlannerTest do
  use ExUnit.Case, async: true

  alias Command.PromptSets.WorkspacePlanner
  alias Command.PromptSets.ExecutionPlan

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp make_prompt_set(prompts, config \\ %{}) do
    %{
      id: "test-prompt-set-id",
      prompts: prompts,
      config: config
    }
  end

  defp default_config do
    %{
      "target_repos" => [
        %{"name" => "command", "path" => "/tmp/command", "default" => true},
        %{"name" => "flowstone", "path" => "/tmp/flowstone"}
      ],
      "repo_groups" => %{
        "pipeline" => ["command", "flowstone"]
      },
      "branch_strategy" => %{
        "mode" => "feature_branch",
        "auto_pr" => false
      },
      "partial_success_policy" => %{
        "mode" => "continue",
        "min_repos_percent" => 50
      },
      "workspace_root" => "/tmp/workspace"
    }
  end

  # ---------------------------------------------------------------------------
  # Tests: Sequential default
  # ---------------------------------------------------------------------------

  describe "plan/2 sequential default" do
    test "sequential default when depends_on absent" do
      prompts = [
        %{"num" => "01", "name" => "A", "file" => "01.md"},
        %{"num" => "02", "name" => "B", "file" => "02.md"},
        %{"num" => "03", "name" => "C", "file" => "03.md"}
      ]

      prompt_set = make_prompt_set(prompts, default_config())
      config = %{max_concurrency: 3, fail_fast: false}

      assert %ExecutionPlan{} = plan = WorkspacePlanner.plan(prompt_set, config)

      # Without explicit depends_on, sequential inference -> one prompt per wave
      assert length(plan.execution_waves) == 3
      assert Enum.at(plan.execution_waves, 0).prompts == ["01"]
      assert Enum.at(plan.execution_waves, 1).prompts == ["02"]
      assert Enum.at(plan.execution_waves, 2).prompts == ["03"]

      # Single-prompt waves are not parallel
      assert Enum.at(plan.execution_waves, 0).parallel == false
      assert Enum.at(plan.execution_waves, 1).parallel == false
      assert Enum.at(plan.execution_waves, 2).parallel == false
    end
  end

  # ---------------------------------------------------------------------------
  # Tests: Parallel waves
  # ---------------------------------------------------------------------------

  describe "plan/2 parallel waves" do
    test "parallel waves generated when dependencies allow" do
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => [], "file" => "01.md"},
        %{"num" => "02", "name" => "B", "depends_on" => [], "file" => "02.md"},
        %{"num" => "03", "name" => "C", "depends_on" => [], "file" => "03.md"},
        %{"num" => "04", "name" => "D", "depends_on" => ["01", "02", "03"], "file" => "04.md"}
      ]

      prompt_set = make_prompt_set(prompts, default_config())
      config = %{max_concurrency: 3, fail_fast: false}

      assert %ExecutionPlan{} = plan = WorkspacePlanner.plan(prompt_set, config)

      assert length(plan.execution_waves) == 2
      assert Enum.at(plan.execution_waves, 0).prompts == ["01", "02", "03"]
      assert Enum.at(plan.execution_waves, 0).parallel == true
      assert Enum.at(plan.execution_waves, 1).prompts == ["04"]
      assert Enum.at(plan.execution_waves, 1).parallel == false
    end
  end

  # ---------------------------------------------------------------------------
  # Tests: Repo conflicts
  # ---------------------------------------------------------------------------

  describe "plan/2 repo conflicts" do
    test "repo conflicts serialized into waves" do
      prompts = [
        %{
          "num" => "01",
          "name" => "A",
          "depends_on" => [],
          "file" => "01.md",
          "target_repos" => ["command"]
        },
        %{
          "num" => "02",
          "name" => "B",
          "depends_on" => [],
          "file" => "02.md",
          "target_repos" => ["flowstone"]
        },
        %{
          "num" => "03",
          "name" => "C",
          "depends_on" => [],
          "file" => "03.md",
          "target_repos" => ["command"]
        }
      ]

      prompt_set = make_prompt_set(prompts, default_config())
      config = %{max_concurrency: 3, fail_fast: false}

      assert %ExecutionPlan{} = plan = WorkspacePlanner.plan(prompt_set, config)

      # 01 and 03 both target "command" -> must be serialized
      # 02 targets "flowstone" only -> can run in parallel with 01
      # Expected: wave 0: [01, 02], wave 1: [03]
      assert length(plan.execution_waves) == 2
      wave_0_prompts = Enum.at(plan.execution_waves, 0).prompts
      wave_1_prompts = Enum.at(plan.execution_waves, 1).prompts

      assert "01" in wave_0_prompts
      assert "02" in wave_0_prompts
      assert "03" in wave_1_prompts

      # Verify repo conflicts are recorded
      assert length(plan.repo_conflicts) > 0

      command_conflict =
        Enum.find(plan.repo_conflicts, fn c -> c.repo == "command" end)

      assert command_conflict != nil
      assert Enum.sort(command_conflict.prompts) == ["01", "03"]
      assert command_conflict.serialized == true
    end
  end

  # ---------------------------------------------------------------------------
  # Tests: prompt_repo_map
  # ---------------------------------------------------------------------------

  describe "plan/2 prompt_repo_map" do
    test "prompt_repo_map reflects group expansion" do
      prompts = [
        %{
          "num" => "01",
          "name" => "A",
          "depends_on" => [],
          "file" => "01.md",
          "target_repos" => ["@pipeline"]
        },
        %{
          "num" => "02",
          "name" => "B",
          "depends_on" => [],
          "file" => "02.md",
          "target_repos" => ["command"]
        }
      ]

      prompt_set = make_prompt_set(prompts, default_config())
      config = %{max_concurrency: 3, fail_fast: false}

      plan = WorkspacePlanner.plan(prompt_set, config)

      # @pipeline expands to ["command", "flowstone"]
      assert Enum.sort(plan.prompt_repo_map["01"]) == ["command", "flowstone"]
      assert plan.prompt_repo_map["02"] == ["command"]
    end
  end

  # ---------------------------------------------------------------------------
  # Tests: branch_plan
  # ---------------------------------------------------------------------------

  describe "plan/2 branch_plan" do
    test "branch_plan resolves strategy and pr_warning" do
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => [], "file" => "01.md"}
      ]

      config_with_branch =
        Map.merge(default_config(), %{
          "branch_strategy" => %{
            "mode" => "feature_branch",
            "auto_pr" => true
          }
        })

      prompt_set = make_prompt_set(prompts, config_with_branch)
      config = %{max_concurrency: 3, fail_fast: false}

      plan = WorkspacePlanner.plan(prompt_set, config)

      assert plan.branch_plan.strategy == "feature_branch"
      assert plan.branch_plan.pr_requested == true
      # pr_effective may differ from requested (e.g., auto_pr not yet supported)
    end

    test "branch_plan defaults to direct strategy when not configured" do
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => [], "file" => "01.md"}
      ]

      prompt_set = make_prompt_set(prompts, %{})
      config = %{max_concurrency: 3, fail_fast: false}

      plan = WorkspacePlanner.plan(prompt_set, config)

      assert plan.branch_plan.strategy == "direct"
      assert plan.branch_plan.pr_requested == false
    end
  end

  # ---------------------------------------------------------------------------
  # Tests: partial_success_plan
  # ---------------------------------------------------------------------------

  describe "plan/2 partial_success_plan" do
    test "partial_success_plan reflects policy and thresholds" do
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => [], "file" => "01.md"}
      ]

      config_with_policy =
        Map.merge(default_config(), %{
          "partial_success_policy" => %{
            "mode" => "require_all",
            "min_repos_percent" => 100
          }
        })

      prompt_set = make_prompt_set(prompts, config_with_policy)
      config = %{max_concurrency: 3, fail_fast: false}

      plan = WorkspacePlanner.plan(prompt_set, config)

      assert plan.partial_success_plan.mode == "require_all"
      assert plan.partial_success_plan.min_repos_percent == 100
    end

    test "partial_success_plan defaults when no policy configured" do
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => [], "file" => "01.md"}
      ]

      prompt_set = make_prompt_set(prompts, %{})
      config = %{max_concurrency: 3, fail_fast: false}

      plan = WorkspacePlanner.plan(prompt_set, config)

      assert plan.partial_success_plan.mode == "continue"
      assert plan.partial_success_plan.min_repos_percent == 50
      assert plan.partial_success_plan.exit_code_on_partial == 6
    end
  end

  # ---------------------------------------------------------------------------
  # Tests: changeset_plan
  # ---------------------------------------------------------------------------

  describe "plan/2 changeset_plan" do
    test "changeset_plan includes run and prompt changesets" do
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => [], "file" => "01.md"},
        %{"num" => "02", "name" => "B", "depends_on" => [], "file" => "02.md"}
      ]

      prompt_set = make_prompt_set(prompts, default_config())
      config = %{max_concurrency: 3, fail_fast: false}

      plan = WorkspacePlanner.plan(prompt_set, config)

      assert plan.changeset_plan.run_changeset == true
      assert plan.changeset_plan.prompt_changesets == true
    end
  end

  # ---------------------------------------------------------------------------
  # Tests: Plan metadata
  # ---------------------------------------------------------------------------

  describe "plan/2 metadata" do
    test "plan includes version and prompt_set_id" do
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => [], "file" => "01.md"}
      ]

      prompt_set = make_prompt_set(prompts, default_config())
      config = %{max_concurrency: 3, fail_fast: false}

      plan = WorkspacePlanner.plan(prompt_set, config)

      assert plan.version == "1.0.0"
      assert plan.prompt_set_id == "test-prompt-set-id"
    end

    test "plan includes max_concurrency and fail_fast from config" do
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => [], "file" => "01.md"}
      ]

      prompt_set = make_prompt_set(prompts, default_config())
      config = %{max_concurrency: 5, fail_fast: true}

      plan = WorkspacePlanner.plan(prompt_set, config)

      assert plan.max_concurrency == 5
      assert plan.fail_fast == true
    end

    test "plan includes workspace_repos and affected_repos" do
      prompts = [
        %{
          "num" => "01",
          "name" => "A",
          "depends_on" => [],
          "file" => "01.md",
          "target_repos" => ["command"]
        }
      ]

      prompt_set = make_prompt_set(prompts, default_config())
      config = %{max_concurrency: 3, fail_fast: false}

      plan = WorkspacePlanner.plan(prompt_set, config)

      assert Enum.sort(plan.workspace_repos) == ["command", "flowstone"]
      assert plan.affected_repos == ["command"]
    end
  end

  # ---------------------------------------------------------------------------
  # Tests: Error propagation
  # ---------------------------------------------------------------------------

  describe "plan/2 error cases" do
    test "returns error for circular dependencies" do
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => ["02"], "file" => "01.md"},
        %{"num" => "02", "name" => "B", "depends_on" => ["01"], "file" => "02.md"}
      ]

      prompt_set = make_prompt_set(prompts, default_config())
      config = %{max_concurrency: 3, fail_fast: false}

      assert {:error, :cycle_detected} = WorkspacePlanner.plan(prompt_set, config)
    end

    test "returns error for missing dependencies" do
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => ["99"], "file" => "01.md"}
      ]

      prompt_set = make_prompt_set(prompts, default_config())
      config = %{max_concurrency: 3, fail_fast: false}

      assert {:error, {:missing_dependencies, ["99"]}} =
               WorkspacePlanner.plan(prompt_set, config)
    end
  end
end
