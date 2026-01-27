defmodule Command.PromptSets.ExecutorTest do
  use ExUnit.Case, async: true

  alias Command.PromptSets.Executor
  alias Command.PromptSets.ExecutionPlan

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp make_plan(waves, opts \\ []) do
    %ExecutionPlan{
      version: "1.0.0",
      prompt_set_id: "test-set-id",
      execution_waves:
        Enum.with_index(waves, fn prompts, idx ->
          %{wave: idx, prompts: prompts, parallel: length(prompts) > 1}
        end),
      max_concurrency: Keyword.get(opts, :max_concurrency, 3),
      fail_fast: Keyword.get(opts, :fail_fast, false)
    }
  end

  # ---------------------------------------------------------------------------
  # Tests: FlowStone DAG building
  # ---------------------------------------------------------------------------

  describe "build_flowstone_dag/3" do
    test "execution waves converted to FlowStone parallel groups" do
      plan = make_plan([["01", "02", "03"], ["04"]])
      run = %{id: "run-123"}

      assert {:ok, dag} = Executor.build_flowstone_dag(plan, run)

      # DAG should have nodes for each prompt
      assert length(dag.nodes) == 4
      node_names = Enum.map(dag.nodes, & &1.name) |> Enum.sort()
      assert node_names == ["prompt_01", "prompt_02", "prompt_03", "prompt_04"]
    end

    test "dependencies encoded as DAG edges" do
      plan = make_plan([["01", "02"], ["03"]])
      run = %{id: "run-123"}

      assert {:ok, dag} = Executor.build_flowstone_dag(plan, run)

      # Prompt 03 is in wave 1, so it depends on all prompts in wave 0
      prompt_03_node = Enum.find(dag.nodes, &(&1.name == "prompt_03"))
      assert prompt_03_node != nil
      assert Enum.sort(prompt_03_node.depends_on) == ["prompt_01", "prompt_02"]

      # Prompts 01 and 02 are in wave 0, so they have no dependencies
      prompt_01_node = Enum.find(dag.nodes, &(&1.name == "prompt_01"))
      assert prompt_01_node.depends_on == []

      prompt_02_node = Enum.find(dag.nodes, &(&1.name == "prompt_02"))
      assert prompt_02_node.depends_on == []
    end

    test "max_concurrency passed to FlowStone executor config" do
      plan = make_plan([["01", "02", "03"]], max_concurrency: 5)
      run = %{id: "run-123"}

      assert {:ok, dag} = Executor.build_flowstone_dag(plan, run)
      assert dag.config.max_concurrency == 5
    end

    test "fail_fast passed to FlowStone executor config" do
      plan = make_plan([["01"]], fail_fast: true)
      run = %{id: "run-123"}

      assert {:ok, dag} = Executor.build_flowstone_dag(plan, run)
      assert dag.config.fail_fast == true
    end

    test "no custom Task.async usage in planner" do
      # Verify the Executor module source does not use Task.async in executable code.
      # We strip comments and moduledoc/doc strings first, then check.
      source_path =
        Path.join([
          File.cwd!(),
          "lib",
          "command",
          "prompt_sets",
          "executor.ex"
        ])

      {:ok, source} = File.read(source_path)

      # Remove @moduledoc and @doc heredoc strings, and inline comments
      code_only =
        source
        |> String.replace(~r/@moduledoc\s+"""[\s\S]*?"""/, "")
        |> String.replace(~r/@doc\s+"""[\s\S]*?"""/, "")
        |> String.replace(~r/#.*$/, "")

      refute code_only =~ "Task.async"
      refute code_only =~ "Task.async_stream"
      refute code_only =~ "Task.Supervisor"
    end

    test "single wave produces correct DAG" do
      plan = make_plan([["01"]])
      run = %{id: "run-123"}

      assert {:ok, dag} = Executor.build_flowstone_dag(plan, run)
      assert length(dag.nodes) == 1

      node = hd(dag.nodes)
      assert node.name == "prompt_01"
      assert node.depends_on == []
    end

    test "three waves produce correct dependency chain" do
      plan = make_plan([["01"], ["02"], ["03"]])
      run = %{id: "run-123"}

      assert {:ok, dag} = Executor.build_flowstone_dag(plan, run)

      prompt_01 = Enum.find(dag.nodes, &(&1.name == "prompt_01"))
      prompt_02 = Enum.find(dag.nodes, &(&1.name == "prompt_02"))
      prompt_03 = Enum.find(dag.nodes, &(&1.name == "prompt_03"))

      assert prompt_01.depends_on == []
      assert prompt_02.depends_on == ["prompt_01"]
      assert prompt_03.depends_on == ["prompt_02"]
    end

    test "DAG includes run_id and prompt_set_id metadata" do
      plan = make_plan([["01"]])
      run = %{id: "run-456"}

      assert {:ok, dag} = Executor.build_flowstone_dag(plan, run)
      assert dag.metadata.run_id == "run-456"
      assert dag.metadata.prompt_set_id == "test-set-id"
    end

    test "nodes include prompt_num in metadata" do
      plan = make_plan([["01", "02"]])
      run = %{id: "run-123"}

      assert {:ok, dag} = Executor.build_flowstone_dag(plan, run)

      prompt_01 = Enum.find(dag.nodes, &(&1.name == "prompt_01"))
      assert prompt_01.metadata.prompt_num == "01"
      assert prompt_01.metadata.wave == 0

      prompt_02 = Enum.find(dag.nodes, &(&1.name == "prompt_02"))
      assert prompt_02.metadata.prompt_num == "02"
      assert prompt_02.metadata.wave == 0
    end

    test "options are passed through to DAG config" do
      plan = make_plan([["01"]])
      run = %{id: "run-123"}
      opts = [timeout: 30_000, dry_run: true]

      assert {:ok, dag} = Executor.build_flowstone_dag(plan, run, opts)
      assert dag.config.timeout == 30_000
      assert dag.config.dry_run == true
    end
  end
end
