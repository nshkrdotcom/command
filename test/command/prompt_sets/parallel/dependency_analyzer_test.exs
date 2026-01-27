defmodule Command.PromptSets.Parallel.DependencyAnalyzerTest do
  use ExUnit.Case, async: true

  alias Command.PromptSets.Parallel.DependencyAnalyzer

  describe "analyze/1" do
    test "no dependencies -> all prompts in wave 0" do
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => []},
        %{"num" => "02", "name" => "B", "depends_on" => []},
        %{"num" => "03", "name" => "C", "depends_on" => []}
      ]

      assert {:ok, waves} = DependencyAnalyzer.analyze(prompts)
      assert waves == [["01", "02", "03"]]
    end

    test "linear chain (1->2->3) -> three waves" do
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => []},
        %{"num" => "02", "name" => "B", "depends_on" => ["01"]},
        %{"num" => "03", "name" => "C", "depends_on" => ["02"]}
      ]

      assert {:ok, waves} = DependencyAnalyzer.analyze(prompts)
      assert waves == [["01"], ["02"], ["03"]]
    end

    test "fork pattern (1->{2,3}) -> wave 0: [1], wave 1: [2,3]" do
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => []},
        %{"num" => "02", "name" => "B", "depends_on" => ["01"]},
        %{"num" => "03", "name" => "C", "depends_on" => ["01"]}
      ]

      assert {:ok, waves} = DependencyAnalyzer.analyze(prompts)
      assert waves == [["01"], ["02", "03"]]
    end

    test "join pattern ({1,2}->3) -> wave 0: [1,2], wave 1: [3]" do
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => []},
        %{"num" => "02", "name" => "B", "depends_on" => []},
        %{"num" => "03", "name" => "C", "depends_on" => ["01", "02"]}
      ]

      assert {:ok, waves} = DependencyAnalyzer.analyze(prompts)
      assert waves == [["01", "02"], ["03"]]
    end

    test "diamond pattern (1->{2,3}->4) -> three waves" do
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => []},
        %{"num" => "02", "name" => "B", "depends_on" => ["01"]},
        %{"num" => "03", "name" => "C", "depends_on" => ["01"]},
        %{"num" => "04", "name" => "D", "depends_on" => ["02", "03"]}
      ]

      assert {:ok, waves} = DependencyAnalyzer.analyze(prompts)
      assert waves == [["01"], ["02", "03"], ["04"]]
    end

    test "cycle detection returns error" do
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => ["02"]},
        %{"num" => "02", "name" => "B", "depends_on" => ["01"]}
      ]

      assert {:error, :cycle_detected} = DependencyAnalyzer.analyze(prompts)
    end

    test "missing dependency returns error" do
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => ["99"]}
      ]

      assert {:error, {:missing_dependencies, ["99"]}} = DependencyAnalyzer.analyze(prompts)
    end

    test "self-dependency returns error" do
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => ["01"]}
      ]

      assert {:error, :cycle_detected} = DependencyAnalyzer.analyze(prompts)
    end

    test "empty prompt list returns empty waves" do
      assert {:ok, []} = DependencyAnalyzer.analyze([])
    end

    test "single prompt with no dependencies returns single wave" do
      prompts = [%{"num" => "01", "name" => "A", "depends_on" => []}]

      assert {:ok, waves} = DependencyAnalyzer.analyze(prompts)
      assert waves == [["01"]]
    end

    test "complex graph with multiple roots and shared dependencies" do
      # Graph: 01, 02 independent; 03 depends on 01; 04 depends on 01,02; 05 depends on 03,04
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => []},
        %{"num" => "02", "name" => "B", "depends_on" => []},
        %{"num" => "03", "name" => "C", "depends_on" => ["01"]},
        %{"num" => "04", "name" => "D", "depends_on" => ["01", "02"]},
        %{"num" => "05", "name" => "E", "depends_on" => ["03", "04"]}
      ]

      assert {:ok, waves} = DependencyAnalyzer.analyze(prompts)
      assert waves == [["01", "02"], ["03", "04"], ["05"]]
    end

    test "three-node cycle detection" do
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => ["03"]},
        %{"num" => "02", "name" => "B", "depends_on" => ["01"]},
        %{"num" => "03", "name" => "C", "depends_on" => ["02"]}
      ]

      assert {:error, :cycle_detected} = DependencyAnalyzer.analyze(prompts)
    end

    test "multiple missing dependencies reported" do
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => ["88", "99"]}
      ]

      assert {:error, {:missing_dependencies, missing}} = DependencyAnalyzer.analyze(prompts)
      assert Enum.sort(missing) == ["88", "99"]
    end
  end

  describe "infer_sequential_dependencies/1" do
    test "prompts without depends_on get sequential dependencies" do
      prompts = [
        %{"num" => "01", "name" => "A"},
        %{"num" => "02", "name" => "B"},
        %{"num" => "03", "name" => "C"}
      ]

      result = DependencyAnalyzer.infer_sequential_dependencies(prompts)

      assert Enum.at(result, 0)["depends_on"] == []
      assert Enum.at(result, 1)["depends_on"] == ["01"]
      assert Enum.at(result, 2)["depends_on"] == ["02"]
    end

    test "prompts with explicit depends_on are left unchanged" do
      prompts = [
        %{"num" => "01", "name" => "A", "depends_on" => []},
        %{"num" => "02", "name" => "B", "depends_on" => []},
        %{"num" => "03", "name" => "C", "depends_on" => ["01"]}
      ]

      result = DependencyAnalyzer.infer_sequential_dependencies(prompts)

      assert Enum.at(result, 0)["depends_on"] == []
      assert Enum.at(result, 1)["depends_on"] == []
      assert Enum.at(result, 2)["depends_on"] == ["01"]
    end

    test "mixed explicit and implicit dependencies" do
      prompts = [
        %{"num" => "01", "name" => "A"},
        %{"num" => "02", "name" => "B", "depends_on" => []},
        %{"num" => "03", "name" => "C"}
      ]

      result = DependencyAnalyzer.infer_sequential_dependencies(prompts)

      assert Enum.at(result, 0)["depends_on"] == []
      # Explicit empty - left as is
      assert Enum.at(result, 1)["depends_on"] == []
      # No depends_on key - infer from previous
      assert Enum.at(result, 2)["depends_on"] == ["02"]
    end
  end
end
