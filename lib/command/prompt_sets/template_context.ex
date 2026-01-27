defmodule Command.PromptSets.TemplateContext do
  @moduledoc """
  Builds template context from various configuration sources.

  The context is built by merging values in the following precedence order
  (later values override earlier):

  1. **Built-in variables** — always available (timestamp, date, prompt_num, etc.)
  2. **Prompt set config** — project-level defaults from `prompt_set.config`
  3. **Run config** — run-specific overrides from `prompt_set_run.config_snapshot`
  4. **Step config** — prompt-specific values from `prompt_def.template_vars`

  String keys are atomized for consistent access in templates.
  Nested maps are deep-merged.
  """

  alias Command.PromptSets.{PromptSet, PromptSetRun}

  @doc """
  Builds a complete template context for a prompt step.

  ## Parameters

  - `run` — The `PromptSetRun` with preloaded `prompt_set`
  - `prompt_num` — The prompt number (string, e.g., `"01"`)
  - `repo_ctx` — Optional map with `:current_repo`, `:current_repo_path`, `:workspace_root`

  ## Returns

  A flat map of atom-keyed values ready for template rendering.
  Also includes a `config` key containing the full resolved config
  for nested access like `{{config.model}}`.
  """
  @spec build(PromptSetRun.t(), String.t(), map()) :: map()
  def build(%PromptSetRun{} = run, prompt_num, repo_ctx \\ %{}) do
    prompt_def = get_prompt_def(run.prompt_set, prompt_num)

    # Build context with merge precedence:
    # built_in < prompt_set config < run config < step config < repo_ctx overrides
    context =
      built_in_vars(run, prompt_num, repo_ctx)
      |> deep_merge(atomize_keys(run.prompt_set.config || %{}))
      |> deep_merge(atomize_keys(run.config_snapshot || %{}))
      |> deep_merge(atomize_keys(prompt_def["template_vars"] || %{}))
      |> deep_merge(repo_ctx_overrides(repo_ctx))

    # Expose the resolved config for nested access
    resolved_config =
      atomize_keys(run.prompt_set.config || %{})
      |> deep_merge(atomize_keys(run.config_snapshot || %{}))
      |> deep_merge(atomize_keys(prompt_def["template_vars"] || %{}))

    Map.put(context, :config, resolved_config)
  end

  @doc """
  Returns built-in variables available to all templates.

  These are always present regardless of configuration.
  """
  @spec built_in_vars(PromptSetRun.t(), String.t(), map()) :: map()
  def built_in_vars(%PromptSetRun{} = run, prompt_num, repo_ctx \\ %{}) do
    prompt_def = get_prompt_def(run.prompt_set, prompt_num)

    %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      date: Date.utc_today() |> Date.to_iso8601(),
      prompt_num: prompt_num,
      prompt_name: prompt_def["name"],
      run_id: run.id,
      phase: prompt_def["phase"],
      phase_name: get_phase_name(run.prompt_set, prompt_def["phase"]),
      target_repos: prompt_def["target_repos"],
      current_repo: repo_ctx[:current_repo],
      current_repo_path: repo_ctx[:current_repo_path],
      workspace_root:
        repo_ctx[:workspace_root] ||
          get_in(run.prompt_set.config || %{}, ["workspace_root"])
    }
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  # Extracts non-nil repo context values for final override merge
  defp repo_ctx_overrides(repo_ctx) when is_map(repo_ctx) do
    repo_ctx
    |> Map.take([:current_repo, :current_repo_path, :workspace_root])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp repo_ctx_overrides(_), do: %{}

  defp get_prompt_def(%PromptSet{} = prompt_set, prompt_num) do
    Enum.find(prompt_set.prompts || [], %{}, fn p -> p["num"] == prompt_num end)
  end

  defp get_phase_name(%PromptSet{} = prompt_set, phase) do
    (prompt_set.phase_names || %{})
    |> Map.get(to_string(phase), "Phase #{phase}")
  end

  @doc false
  @spec deep_merge(map(), map()) :: map()
  def deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn
      _k, l, r when is_map(l) and is_map(r) -> deep_merge(l, r)
      _k, _l, r -> r
    end)
  end

  @doc false
  @spec atomize_keys(map()) :: map()
  def atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), atomize_keys(v)}
      {k, v} -> {k, atomize_keys(v)}
    end)
  end

  def atomize_keys(list) when is_list(list), do: Enum.map(list, &atomize_keys/1)
  def atomize_keys(other), do: other
end
