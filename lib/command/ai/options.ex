defmodule Command.AI.Options do
  @moduledoc """
  Option layering for provider-specific AI execution.

  Builds merged option maps for AI provider calls by applying configuration
  in a defined precedence order. Later layers override earlier ones.

  ## Layering Order (later wins)

  1. **Prompt-set defaults** — Defined in `prompt_sets.config`
  2. **Run-level overrides** — Passed to `create_run/2`
  3. **Prompt-level overrides** — Per-prompt config in `prompts` JSONB

  ## Supported Keys

  - `:permission_mode` — Tool permission gating (`:auto`, `:confirm`, `:deny`)
  - `:allowed_tools` — List of tool names the prompt may use
  - `:claude_opts` — Claude-specific option map (model, max_tokens, etc.)
  - `:codex_opts` — Codex-specific option map (model, etc.)
  - `:codex_thread_opts` — Codex thread-specific option map

  ## Examples

      # Prompt-set defaults
      defaults = %{
        permission_mode: :auto,
        claude_opts: %{model: "claude-sonnet-4-20250514", max_tokens: 4096}
      }

      # Run overrides
      run_opts = %{
        claude_opts: %{max_tokens: 8192}
      }

      # Prompt overrides
      prompt_opts = %{
        permission_mode: :confirm,
        claude_opts: %{temperature: 0.5}
      }

      merged = Command.AI.Options.merge(defaults, run_opts, prompt_opts)
      # => %{
      #   permission_mode: :confirm,
      #   claude_opts: %{model: "claude-sonnet-4-20250514", max_tokens: 8192, temperature: 0.5},
      #   ...
      # }
  """

  @type permission_mode :: :auto | :confirm | :deny
  @type provider_opts :: map()

  @type t :: %{
          optional(:permission_mode) => permission_mode(),
          optional(:allowed_tools) => [String.t()],
          optional(:claude_opts) => provider_opts(),
          optional(:codex_opts) => provider_opts(),
          optional(:codex_thread_opts) => provider_opts()
        }

  @provider_opt_keys [:claude_opts, :codex_opts, :codex_thread_opts]

  @doc """
  Merges three layers of options with defined precedence.

  Provider-specific option maps (`:claude_opts`, `:codex_opts`, `:codex_thread_opts`)
  are deep-merged so that nested keys from later layers override earlier ones
  without discarding sibling keys.

  Scalar keys (`:permission_mode`, `:allowed_tools`) use simple last-wins override.

  ## Parameters

  - `prompt_set_defaults` — Base defaults from the prompt set config
  - `run_overrides` — Run-level overrides
  - `prompt_overrides` — Per-prompt overrides (highest precedence)

  ## Returns

  A merged options map.
  """
  @spec merge(map(), map(), map()) :: t()
  def merge(prompt_set_defaults, run_overrides, prompt_overrides) do
    prompt_set_defaults
    |> merge_layer(run_overrides)
    |> merge_layer(prompt_overrides)
  end

  @doc """
  Merges two layers of options with the second layer taking precedence.

  ## Parameters

  - `base` — Base options
  - `overrides` — Override options (higher precedence)

  ## Returns

  A merged options map.
  """
  @spec merge_layer(map(), map()) :: t()
  def merge_layer(base, overrides) when is_map(base) and is_map(overrides) do
    Map.merge(base, overrides, fn
      key, base_val, override_val when key in @provider_opt_keys ->
        deep_merge_maps(base_val, override_val)

      _key, _base_val, override_val ->
        override_val
    end)
  end

  def merge_layer(base, _overrides) when is_map(base), do: base
  def merge_layer(_base, overrides) when is_map(overrides), do: overrides
  def merge_layer(_base, _overrides), do: %{}

  @doc """
  Extracts provider-specific options from the merged options map.

  ## Parameters

  - `opts` — The merged options map
  - `provider` — `:claude` or `:codex`

  ## Returns

  A keyword list suitable for passing to the provider adapter.
  """
  @spec provider_opts(t(), :claude | :codex) :: keyword()
  def provider_opts(opts, :claude) do
    base = Map.get(opts, :claude_opts, %{}) |> map_to_keyword()
    maybe_add_permission(base, opts)
  end

  def provider_opts(opts, :codex) do
    base = Map.get(opts, :codex_opts, %{}) |> map_to_keyword()
    thread_opts = Map.get(opts, :codex_thread_opts, %{}) |> map_to_keyword()

    base
    |> Keyword.put(:thread_opts, thread_opts)
    |> maybe_add_permission(opts)
  end

  @doc """
  Returns the effective permission mode from the options.

  ## Parameters

  - `opts` — The merged options map

  ## Returns

  The permission mode atom, defaulting to `:auto`.
  """
  @spec permission_mode(t()) :: permission_mode()
  def permission_mode(opts) do
    Map.get(opts, :permission_mode, :auto)
  end

  @doc """
  Returns the effective allowed tools list from the options.

  ## Parameters

  - `opts` — The merged options map

  ## Returns

  A list of tool name strings, or `nil` if unrestricted.
  """
  @spec allowed_tools(t()) :: [String.t()] | nil
  def allowed_tools(opts) do
    Map.get(opts, :allowed_tools)
  end

  # Private helpers

  defp deep_merge_maps(base, override) when is_map(base) and is_map(override) do
    Map.merge(base, override, fn
      _key, base_val, override_val when is_map(base_val) and is_map(override_val) ->
        deep_merge_maps(base_val, override_val)

      _key, _base_val, override_val ->
        override_val
    end)
  end

  defp deep_merge_maps(_base, override) when is_map(override), do: override
  defp deep_merge_maps(base, _override) when is_map(base), do: base
  defp deep_merge_maps(_base, _override), do: %{}

  defp map_to_keyword(map) when is_map(map) do
    Enum.map(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} when is_atom(k) -> {k, v}
    end)
  rescue
    ArgumentError -> Enum.map(map, fn {k, v} -> {to_atom_safe(k), v} end)
  end

  defp map_to_keyword(_), do: []

  defp to_atom_safe(k) when is_atom(k), do: k
  defp to_atom_safe(k) when is_binary(k), do: String.to_atom(k)

  defp maybe_add_permission(keyword, opts) do
    case Map.get(opts, :permission_mode) do
      nil -> keyword
      mode -> Keyword.put(keyword, :permission_mode, mode)
    end
  end
end
