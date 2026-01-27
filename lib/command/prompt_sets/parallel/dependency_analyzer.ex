defmodule Command.PromptSets.Parallel.DependencyAnalyzer do
  @moduledoc """
  Analyzes prompt dependencies and builds execution waves.

  Takes a list of prompt definitions (maps with `"num"` and `"depends_on"` keys)
  and produces an ordered list of waves. Each wave is a sorted list of prompt
  numbers that can execute concurrently. Waves execute sequentially.

  ## Dependency Rules

  - `depends_on: []` means no dependencies (can run in wave 0)
  - `depends_on: ["01", "02"]` means wait for both prompts to complete
  - If `depends_on` key is absent, use `infer_sequential_dependencies/1` first

  ## Wave Computation

  Uses Kahn's algorithm (topological sort by in-degree) to group prompts by
  depth in the dependency DAG. Prompts at the same depth form a wave.

  ## Error Cases

  - Circular dependencies: `{:error, :cycle_detected}`
  - Missing dependencies: `{:error, {:missing_dependencies, [missing_nums]}}`
  """

  @type wave :: [String.t()]
  @type waves :: [wave()]

  @doc """
  Analyzes prompt dependencies and returns execution waves.

  Each wave is a sorted list of prompt numbers that can execute concurrently.
  Waves are ordered by dependency depth (wave 0 has no dependencies).

  ## Parameters

  - `prompts` - List of prompt definition maps. Each must have `"num"` and
    `"depends_on"` keys. Use `infer_sequential_dependencies/1` first if
    `depends_on` may be absent.

  ## Returns

  - `{:ok, waves}` - List of waves (each a sorted list of prompt numbers)
  - `{:error, :cycle_detected}` - Circular dependency found
  - `{:error, {:missing_dependencies, [nums]}}` - Referenced prompts don't exist

  ## Examples

      iex> prompts = [
      ...>   %{"num" => "01", "depends_on" => []},
      ...>   %{"num" => "02", "depends_on" => ["01"]},
      ...>   %{"num" => "03", "depends_on" => ["01"]}
      ...> ]
      iex> DependencyAnalyzer.analyze(prompts)
      {:ok, [["01"], ["02", "03"]]}
  """
  @spec analyze([map()]) :: {:ok, waves()} | {:error, term()}
  def analyze([]), do: {:ok, []}

  def analyze(prompts) do
    graph = build_graph(prompts)

    with :ok <- validate_dependencies_exist(graph, prompts),
         :ok <- validate_no_self_dependencies(graph) do
      compute_waves(graph)
    end
  end

  @doc """
  Infers sequential dependencies for prompts missing `depends_on`.

  When `depends_on` key is absent from a prompt, the prompt is assumed to
  depend on the previous prompt in the list (sequential execution). The first
  prompt in the list gets an empty dependency list.

  Prompts that already have a `depends_on` key (even if empty) are unchanged.

  ## Parameters

  - `prompts` - List of prompt definition maps

  ## Returns

  List of prompt maps with `depends_on` key guaranteed present.

  ## Examples

      iex> prompts = [
      ...>   %{"num" => "01", "name" => "A"},
      ...>   %{"num" => "02", "name" => "B"}
      ...> ]
      iex> DependencyAnalyzer.infer_sequential_dependencies(prompts)
      [
        %{"num" => "01", "name" => "A", "depends_on" => []},
        %{"num" => "02", "name" => "B", "depends_on" => ["01"]}
      ]
  """
  @spec infer_sequential_dependencies([map()]) :: [map()]
  def infer_sequential_dependencies(prompts) do
    prompts
    |> Enum.with_index()
    |> Enum.map(fn {prompt, index} ->
      infer_dependency_for_prompt(prompt, prompts, index)
    end)
  end

  defp infer_dependency_for_prompt(prompt, _prompts, _index)
       when is_map_key(prompt, "depends_on") do
    prompt
  end

  defp infer_dependency_for_prompt(prompt, prompts, 0) do
    _ = prompts
    Map.put(prompt, "depends_on", [])
  end

  defp infer_dependency_for_prompt(prompt, prompts, index) do
    prev_num = Enum.at(prompts, index - 1)["num"]
    Map.put(prompt, "depends_on", [prev_num])
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  # Build adjacency map: %{prompt_num => [dependency_nums]}
  defp build_graph(prompts) do
    Enum.reduce(prompts, %{}, fn prompt, acc ->
      num = prompt["num"]
      deps = prompt["depends_on"] || []
      Map.put(acc, num, deps)
    end)
  end

  # Validate all referenced dependencies actually exist in the prompt list
  defp validate_dependencies_exist(graph, prompts) do
    all_nums = Enum.map(prompts, & &1["num"]) |> MapSet.new()

    missing =
      graph
      |> Enum.flat_map(fn {_num, deps} -> deps end)
      |> Enum.reject(&MapSet.member?(all_nums, &1))
      |> Enum.uniq()
      |> Enum.sort()

    case missing do
      [] -> :ok
      _ -> {:error, {:missing_dependencies, missing}}
    end
  end

  # Validate no prompt depends on itself
  defp validate_no_self_dependencies(graph) do
    self_deps =
      Enum.filter(graph, fn {num, deps} -> num in deps end)
      |> Enum.map(fn {num, _} -> num end)

    case self_deps do
      [] -> :ok
      _ -> {:error, :cycle_detected}
    end
  end

  # Compute waves using Kahn's algorithm (topological sort by in-degree).
  # Returns {:ok, waves} or {:error, :cycle_detected}
  defp compute_waves(graph) do
    in_degrees = compute_in_degrees(graph)
    do_compute_waves(graph, in_degrees, [])
  end

  # Compute in-degree for each node: how many dependencies does it have?
  defp compute_in_degrees(graph) do
    Map.new(graph, fn {num, deps} -> {num, length(deps)} end)
  end

  # Kahn's algorithm: repeatedly find nodes with in-degree 0, remove them,
  # decrement dependents. Each iteration produces one wave.
  defp do_compute_waves(_graph, in_degrees, waves) when map_size(in_degrees) == 0 do
    {:ok, Enum.reverse(waves)}
  end

  defp do_compute_waves(graph, in_degrees, waves) do
    # Find all nodes with in-degree 0 (ready to execute)
    wave =
      in_degrees
      |> Enum.filter(fn {_num, degree} -> degree == 0 end)
      |> Enum.map(fn {num, _} -> num end)
      |> Enum.sort()

    case wave do
      [] ->
        # Remaining nodes all have dependencies that can't be satisfied -> cycle
        {:error, :cycle_detected}

      _ ->
        # Remove wave nodes from in_degrees
        remaining = Map.drop(in_degrees, wave)

        # For each remaining node, decrement in-degree for each dependency
        # that was in the current wave
        wave_set = MapSet.new(wave)

        updated_degrees =
          Map.new(remaining, fn {num, _degree} ->
            deps = Map.get(graph, num, [])
            satisfied = Enum.count(deps, &MapSet.member?(wave_set, &1))
            {num, Map.get(remaining, num) - satisfied}
          end)

        do_compute_waves(graph, updated_degrees, [wave | waves])
    end
  end
end
