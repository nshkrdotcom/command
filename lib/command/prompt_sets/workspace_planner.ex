defmodule Command.PromptSets.WorkspacePlanner do
  @moduledoc """
  Generates an `ExecutionPlan` per ADR-0010 Section 11.

  This module is a planner only - it analyzes prompt dependencies, detects
  repo conflicts, and produces a plan that FlowStone can execute. It does not
  perform any execution itself.

  ## Planning Steps

  1. Infer sequential dependencies for prompts without explicit `depends_on`
  2. Expand repo groups (`@pipeline` -> `["command", "flowstone"]`)
  3. Build prompt-to-repo mapping
  4. Detect repo conflicts (prompts targeting the same repo)
  5. Add implicit dependencies for repo conflict serialization
  6. Analyze final dependency graph to compute execution waves
  7. Assemble the `ExecutionPlan` struct

  ## Usage

      prompt_set = %{id: "...", prompts: [...], config: %{...}}
      config = %{max_concurrency: 3, fail_fast: false}

      case WorkspacePlanner.plan(prompt_set, config) do
        %ExecutionPlan{} = plan -> # success
        {:error, reason} -> # dependency error
      end
  """

  alias Command.PromptSets.ExecutionPlan
  alias Command.PromptSets.Parallel.DependencyAnalyzer
  alias Command.PromptSets.Parallel.RepoConflictDetector

  @doc """
  Generates an execution plan for the given prompt set.

  ## Parameters

  - `prompt_set` - Map or struct with `:id`, `:prompts`, and `:config` keys
  - `config` - Execution config with `:max_concurrency` and `:fail_fast` keys

  ## Returns

  - `%ExecutionPlan{}` on success
  - `{:error, reason}` if dependency analysis fails (cycles, missing deps)
  """
  @spec plan(map(), map()) :: ExecutionPlan.t() | {:error, term()}
  def plan(prompt_set, config) do
    prompts = prompt_set.prompts
    ps_config = prompt_set.config || %{}

    # Step 1: Infer sequential dependencies for prompts without depends_on
    prompts_with_deps = DependencyAnalyzer.infer_sequential_dependencies(prompts)

    # Step 2: Expand repo groups and build prompt_repo_map
    repo_groups = ps_config["repo_groups"] || %{}
    prompt_repo_map = build_prompt_repo_map(prompts_with_deps, repo_groups)

    # Step 3: Detect repo conflicts
    conflicts = RepoConflictDetector.find_conflicts(prompt_repo_map)

    # Step 4: Add implicit dependencies for conflicts
    prompts_serialized =
      RepoConflictDetector.add_conflict_dependencies(prompts_with_deps, conflicts)

    # Step 5: Analyze dependencies to compute waves
    case DependencyAnalyzer.analyze(prompts_serialized) do
      {:ok, waves} ->
        build_plan(prompt_set, config, ps_config, waves, prompt_repo_map, conflicts)

      {:error, _reason} = error ->
        error
    end
  end

  # ---------------------------------------------------------------------------
  # Private: Plan construction
  # ---------------------------------------------------------------------------

  defp build_plan(prompt_set, config, ps_config, waves, prompt_repo_map, conflicts) do
    %ExecutionPlan{
      version: "1.0.0",
      prompt_set_id: prompt_set.id,
      workspace_repos: extract_workspace_repos(ps_config),
      affected_repos: extract_affected_repos(prompt_repo_map),
      prompt_repo_map: prompt_repo_map,
      repo_conflicts: conflicts,
      execution_waves: build_execution_waves(waves),
      branch_plan: resolve_branch_plan(ps_config),
      changeset_plan: resolve_changeset_plan(ps_config),
      partial_success_plan: resolve_partial_success_plan(ps_config),
      max_concurrency: config[:max_concurrency] || 3,
      fail_fast: config[:fail_fast] || false
    }
  end

  # ---------------------------------------------------------------------------
  # Private: Repo mapping
  # ---------------------------------------------------------------------------

  defp build_prompt_repo_map(prompts, repo_groups) do
    Enum.reduce(prompts, %{}, fn prompt, acc ->
      num = prompt["num"]
      raw_repos = prompt["target_repos"] || []
      expanded = expand_repo_refs(raw_repos, repo_groups)
      Map.put(acc, num, expanded)
    end)
  end

  defp expand_repo_refs(refs, repo_groups) do
    refs
    |> Enum.flat_map(fn ref ->
      if String.starts_with?(ref, "@") do
        group_name = String.trim_leading(ref, "@")
        Map.get(repo_groups, group_name, [])
      else
        [ref]
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # ---------------------------------------------------------------------------
  # Private: Workspace repos
  # ---------------------------------------------------------------------------

  defp extract_workspace_repos(ps_config) do
    case ps_config["target_repos"] do
      repos when is_list(repos) ->
        repos
        |> Enum.map(fn
          %{"name" => name} -> name
          name when is_binary(name) -> name
        end)
        |> Enum.sort()

      _ ->
        []
    end
  end

  defp extract_affected_repos(prompt_repo_map) do
    prompt_repo_map
    |> Map.values()
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  # ---------------------------------------------------------------------------
  # Private: Execution waves
  # ---------------------------------------------------------------------------

  defp build_execution_waves(waves) do
    waves
    |> Enum.with_index()
    |> Enum.map(fn {prompts, idx} ->
      %{
        wave: idx,
        prompts: prompts,
        parallel: length(prompts) > 1
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Private: Branch plan
  # ---------------------------------------------------------------------------

  defp resolve_branch_plan(ps_config) do
    branch_strategy = ps_config["branch_strategy"] || %{}
    mode = branch_strategy["mode"] || "direct"
    auto_pr = branch_strategy["auto_pr"] || false

    %{
      strategy: mode,
      pr_requested: auto_pr,
      pr_effective: auto_pr,
      pr_warning: nil
    }
  end

  # ---------------------------------------------------------------------------
  # Private: Changeset plan
  # ---------------------------------------------------------------------------

  defp resolve_changeset_plan(_ps_config) do
    %{
      run_changeset: true,
      prompt_changesets: true
    }
  end

  # ---------------------------------------------------------------------------
  # Private: Partial success plan
  # ---------------------------------------------------------------------------

  defp resolve_partial_success_plan(ps_config) do
    policy = ps_config["partial_success_policy"] || %{}

    %{
      mode: policy["mode"] || "continue",
      min_repos_percent: policy["min_repos_percent"] || 50,
      exit_code_on_partial: policy["exit_code_on_partial"] || 6
    }
  end
end
