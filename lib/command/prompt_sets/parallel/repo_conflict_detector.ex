defmodule Command.PromptSets.Parallel.RepoConflictDetector do
  @moduledoc """
  Detects repository conflicts between prompts and adds implicit dependencies
  to serialize prompts that target the same repository.

  When two prompts target the same repo, they cannot run concurrently because
  both would attempt to modify files and commit to the same repository,
  causing commit conflicts. This module identifies such conflicts and adds
  dependency edges to ensure conflicting prompts run in separate waves.

  ## Algorithm

  1. Build a map of repo -> [prompt_nums] (the prompt_repo_map)
  2. For each repo with >1 prompt, create a conflict record
  3. Add implicit dependencies: for prompts targeting the same repo,
     each prompt depends on the previous one in sorted order

  ## Example

  Prompts 01, 03 both target "command":
  - Conflict: `%{repo: "command", prompts: ["01", "03"], serialized: true}`
  - Implicit dep added: 03 depends_on 01 (if not already)
  """

  @type conflict :: %{
          repo: String.t(),
          prompts: [String.t()],
          serialized: boolean()
        }

  @doc """
  Finds repo conflicts in the given prompts and their resolved repo map.

  ## Parameters

  - `prompt_repo_map` - Map of prompt_num to list of resolved repo names

  ## Returns

  List of conflict descriptors for repos targeted by multiple prompts.
  """
  @spec find_conflicts(%{String.t() => [String.t()]}) :: [conflict()]
  def find_conflicts(prompt_repo_map) do
    # Invert: repo -> [prompt_nums]
    repo_to_prompts =
      Enum.reduce(prompt_repo_map, %{}, fn {prompt_num, repos}, acc ->
        Enum.reduce(repos, acc, fn repo, a ->
          Map.update(a, repo, [prompt_num], &[prompt_num | &1])
        end)
      end)

    repo_to_prompts
    |> Enum.filter(fn {_repo, prompts} -> length(prompts) > 1 end)
    |> Enum.map(fn {repo, prompts} ->
      %{
        repo: repo,
        prompts: Enum.sort(prompts),
        serialized: true
      }
    end)
    |> Enum.sort_by(& &1.repo)
  end

  @doc """
  Adds implicit dependencies to serialize prompts that conflict on repos.

  For each conflicting repo, ensures prompts are chained sequentially
  (in sorted order). Returns updated prompts with additional `depends_on`
  entries.

  ## Parameters

  - `prompts` - List of prompt maps with `"num"` and `"depends_on"` keys
  - `conflicts` - List of conflict descriptors from `find_conflicts/1`

  ## Returns

  Updated list of prompt maps with additional dependencies for serialization.
  """
  @spec add_conflict_dependencies([map()], [conflict()]) :: [map()]
  def add_conflict_dependencies(prompts, []), do: prompts

  def add_conflict_dependencies(prompts, conflicts) do
    # Build a map of additional dependencies from conflicts
    additional_deps = compute_additional_deps(conflicts)

    Enum.map(prompts, fn prompt ->
      num = prompt["num"]
      extra = Map.get(additional_deps, num, [])

      if extra == [] do
        prompt
      else
        existing = prompt["depends_on"] || []
        merged = Enum.uniq(existing ++ extra) |> Enum.sort()
        Map.put(prompt, "depends_on", merged)
      end
    end)
  end

  # For each conflict, chain prompts: second depends on first, third on second, etc.
  defp compute_additional_deps(conflicts) do
    Enum.reduce(conflicts, %{}, fn %{prompts: prompts}, acc ->
      sorted = Enum.sort(prompts)

      sorted
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce(acc, fn [prev, curr], a ->
        Map.update(a, curr, [prev], fn existing ->
          Enum.uniq([prev | existing])
        end)
      end)
    end)
  end
end
