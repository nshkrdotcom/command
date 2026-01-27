defmodule Command.PromptSets.Executor do
  @moduledoc """
  Builds FlowStone DAGs from an `ExecutionPlan`.

  This module is a **planner**, not an executor. It converts execution plans
  (waves of prompts with dependency information) into FlowStone-compatible
  DAG structures. FlowStone handles actual scheduling and execution.

  ## Key Design Constraint

  No `Task.async`, `Task.async_stream`, or `Task.Supervisor` usage is allowed.
  All parallelism is expressed through FlowStone's DAG structure and executor.

  ## DAG Structure

  The produced DAG contains:
  - **Nodes**: One per prompt, named `"prompt_\#{num}"`
  - **Edges**: Dependencies between nodes (derived from wave ordering)
  - **Config**: `max_concurrency`, `fail_fast`, and any passthrough options
  - **Metadata**: `run_id` and `prompt_set_id` for correlation

  ## Usage

      plan = WorkspacePlanner.plan(prompt_set, config)
      {:ok, dag} = Executor.build_flowstone_dag(plan, run)
      # Pass dag to FlowStone.Executor.run/2
  """

  alias Command.PromptSets.ExecutionPlan

  @type dag_node :: %{
          name: String.t(),
          depends_on: [String.t()],
          metadata: map()
        }

  @type dag :: %{
          nodes: [dag_node()],
          config: map(),
          metadata: map()
        }

  @doc """
  Builds a FlowStone-compatible DAG from an execution plan.

  Converts execution waves into a flat list of nodes with dependency edges.
  Each prompt becomes a node named `"prompt_\#{num}"`. Prompts in wave N+1
  depend on all prompts in wave N.

  ## Parameters

  - `plan` - An `ExecutionPlan` struct with `execution_waves`
  - `run` - A map with at minimum `:id` for the current run
  - `opts` - Additional options passed through to DAG config

  ## Returns

  - `{:ok, dag}` - DAG structure with nodes, config, and metadata

  ## Examples

      iex> plan = %ExecutionPlan{execution_waves: [
      ...>   %{wave: 0, prompts: ["01", "02"], parallel: true},
      ...>   %{wave: 1, prompts: ["03"], parallel: false}
      ...> ]}
      iex> {:ok, dag} = Executor.build_flowstone_dag(plan, %{id: "run-1"})
      iex> length(dag.nodes)
      3
  """
  @spec build_flowstone_dag(ExecutionPlan.t(), map(), keyword()) :: {:ok, dag()}
  def build_flowstone_dag(%ExecutionPlan{} = plan, run, opts \\ []) do
    nodes = build_nodes(plan.execution_waves)

    config =
      %{
        max_concurrency: plan.max_concurrency,
        fail_fast: plan.fail_fast
      }
      |> Map.merge(Map.new(opts))

    metadata = %{
      run_id: run.id,
      prompt_set_id: plan.prompt_set_id
    }

    dag = %{
      nodes: nodes,
      config: config,
      metadata: metadata
    }

    {:ok, dag}
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  # Build DAG nodes from execution waves.
  # Each wave's prompts depend on all prompts from the previous wave.
  defp build_nodes(waves) do
    waves
    |> Enum.reduce({[], []}, fn wave, {nodes, prev_wave_names} ->
      wave_nodes =
        Enum.map(wave.prompts, fn prompt_num ->
          %{
            name: "prompt_#{prompt_num}",
            depends_on: prev_wave_names,
            metadata: %{
              prompt_num: prompt_num,
              wave: wave.wave
            }
          }
        end)

      current_wave_names = Enum.map(wave_nodes, & &1.name)
      {nodes ++ wave_nodes, current_wave_names}
    end)
    |> elem(0)
  end
end
