defmodule Command.PromptSets.Parallel.RepoConflictDetectorTest do
  use ExUnit.Case, async: true

  alias Command.PromptSets.Parallel.RepoConflictDetector

  describe "find_conflicts/1" do
    test "no conflicts when prompts target different repos" do
      prompt_repo_map = %{
        "01" => ["command"],
        "02" => ["flowstone"],
        "03" => ["synapse"]
      }

      assert RepoConflictDetector.find_conflicts(prompt_repo_map) == []
    end

    test "detects conflict when two prompts target same repo" do
      prompt_repo_map = %{
        "01" => ["command"],
        "02" => ["command"]
      }

      conflicts = RepoConflictDetector.find_conflicts(prompt_repo_map)
      assert length(conflicts) == 1
      assert hd(conflicts).repo == "command"
      assert hd(conflicts).prompts == ["01", "02"]
      assert hd(conflicts).serialized == true
    end

    test "detects multiple conflicts across repos" do
      prompt_repo_map = %{
        "01" => ["command", "flowstone"],
        "02" => ["command"],
        "03" => ["flowstone"]
      }

      conflicts = RepoConflictDetector.find_conflicts(prompt_repo_map)
      assert length(conflicts) == 2

      command_conflict = Enum.find(conflicts, &(&1.repo == "command"))
      assert command_conflict.prompts == ["01", "02"]

      flowstone_conflict = Enum.find(conflicts, &(&1.repo == "flowstone"))
      assert flowstone_conflict.prompts == ["01", "03"]
    end

    test "no conflicts with empty prompt_repo_map" do
      assert RepoConflictDetector.find_conflicts(%{}) == []
    end

    test "no conflicts when prompts have empty repo lists" do
      prompt_repo_map = %{
        "01" => [],
        "02" => []
      }

      assert RepoConflictDetector.find_conflicts(prompt_repo_map) == []
    end
  end

  describe "add_conflict_dependencies/2" do
    test "no changes when no conflicts" do
      prompts = [
        %{"num" => "01", "depends_on" => []},
        %{"num" => "02", "depends_on" => []}
      ]

      result = RepoConflictDetector.add_conflict_dependencies(prompts, [])
      assert result == prompts
    end

    test "adds dependency for two-prompt conflict" do
      prompts = [
        %{"num" => "01", "depends_on" => []},
        %{"num" => "03", "depends_on" => []}
      ]

      conflicts = [%{repo: "command", prompts: ["01", "03"], serialized: true}]
      result = RepoConflictDetector.add_conflict_dependencies(prompts, conflicts)

      assert Enum.at(result, 0)["depends_on"] == []
      assert "01" in Enum.at(result, 1)["depends_on"]
    end

    test "chains three conflicting prompts" do
      prompts = [
        %{"num" => "01", "depends_on" => []},
        %{"num" => "02", "depends_on" => []},
        %{"num" => "03", "depends_on" => []}
      ]

      conflicts = [%{repo: "command", prompts: ["01", "02", "03"], serialized: true}]
      result = RepoConflictDetector.add_conflict_dependencies(prompts, conflicts)

      assert Enum.at(result, 0)["depends_on"] == []
      assert "01" in Enum.at(result, 1)["depends_on"]
      assert "02" in Enum.at(result, 2)["depends_on"]
    end

    test "preserves existing dependencies" do
      prompts = [
        %{"num" => "01", "depends_on" => []},
        %{"num" => "02", "depends_on" => ["01"]},
        %{"num" => "03", "depends_on" => []}
      ]

      conflicts = [%{repo: "command", prompts: ["01", "03"], serialized: true}]
      result = RepoConflictDetector.add_conflict_dependencies(prompts, conflicts)

      # 02 keeps its existing dependency
      assert Enum.at(result, 1)["depends_on"] == ["01"]
      # 03 gets new dependency on 01
      assert "01" in Enum.at(result, 2)["depends_on"]
    end

    test "does not duplicate existing dependencies" do
      prompts = [
        %{"num" => "01", "depends_on" => []},
        %{"num" => "03", "depends_on" => ["01"]}
      ]

      conflicts = [%{repo: "command", prompts: ["01", "03"], serialized: true}]
      result = RepoConflictDetector.add_conflict_dependencies(prompts, conflicts)

      # 03 already depends on 01, should not duplicate
      deps_03 = Enum.at(result, 1)["depends_on"]
      assert deps_03 == ["01"]
    end
  end
end
