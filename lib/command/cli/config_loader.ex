defmodule Command.CLI.ConfigLoader do
  @moduledoc """
  Loads and validates configuration files for CLI execution.

  Supports both legacy run_prompts.exs format and new multi-repo configurations.
  """

  @type config :: %{
          project_dir: String.t() | nil,
          target_repos: [map()] | nil,
          repo_groups: map() | nil,
          prompts_file: String.t(),
          commit_messages_file: String.t(),
          progress_file: String.t() | nil,
          log_dir: String.t(),
          model: String.t(),
          provider: :claude | :codex,
          allowed_tools: [String.t()],
          permission_mode: atom(),
          prompt_overrides: map() | nil,
          log_mode: :compact | :verbose,
          log_meta: :none | :full,
          events_mode: :compact | :full | :off,
          phase_names: %{pos_integer() => String.t()} | nil,
          workspace_root: String.t() | nil,
          db_enabled: boolean(),
          file_mirror: boolean()
        }

  @type prompt :: %{
          num: String.t(),
          phase: pos_integer(),
          sp: pos_integer(),
          name: String.t(),
          file: String.t(),
          target_repos: [String.t()] | nil,
          target_repos_raw: [String.t()] | nil
        }

  @required_fields [:prompts_file, :commit_messages_file, :log_dir, :model]

  @doc """
  Load configuration file from path.

  Returns {:ok, config} or {:error, reason}.
  """
  @spec load(String.t()) :: {:ok, config()} | {:error, term()}
  def load(path) do
    case File.exists?(path) do
      false ->
        {:error, {:file_not_found, path}}

      true ->
        try do
          {config, _bindings} = Code.eval_file(path)

          case config do
            config when is_map(config) ->
              {:ok, config}

            _ ->
              {:error, :invalid_config}
          end
        rescue
          e ->
            {:error, {:config_error, e}}
        end
    end
  end

  @doc """
  Validate configuration has all required fields.
  """
  @spec validate(config()) :: :ok | {:error, {:missing_fields, [atom()]}}
  def validate(config) do
    missing =
      Enum.filter(@required_fields, fn field ->
        not Map.has_key?(config, field)
      end)

    case missing do
      [] -> :ok
      fields -> {:error, {:missing_fields, fields}}
    end
  end

  @doc """
  Get all prompts from prompts file.
  """
  @spec get_all_prompts(config()) :: {:ok, [prompt()]} | {:error, term()}
  def get_all_prompts(config) do
    prompts_file = config[:prompts_file] || config.prompts_file

    case File.read(prompts_file) do
      {:ok, content} ->
        prompts =
          content
          |> String.split("\n", trim: true)
          |> Enum.reject(&String.starts_with?(&1, "#"))
          |> Enum.map(&parse_prompt_line(&1, config))
          |> Enum.reject(&is_nil/1)

        {:ok, prompts}

      {:error, reason} ->
        {:error, {:file_not_found, prompts_file, reason}}
    end
  end

  @doc """
  Get all prompt numbers in sorted order.
  """
  @spec get_all_nums(config()) :: {:ok, [String.t()]} | {:error, term()}
  def get_all_nums(config) do
    case get_all_prompts(config) do
      {:ok, prompts} ->
        nums =
          prompts
          |> Enum.map(& &1.num)
          |> Enum.sort()

        {:ok, nums}

      error ->
        error
    end
  end

  @doc """
  Get prompt numbers for specific phase.
  """
  @spec get_phase_nums(config(), pos_integer()) :: {:ok, [String.t()]} | {:error, term()}
  def get_phase_nums(config, phase) do
    case get_all_prompts(config) do
      {:ok, prompts} ->
        nums =
          prompts
          |> Enum.filter(&(&1.phase == phase))
          |> Enum.map(& &1.num)
          |> Enum.sort()

        {:ok, nums}

      error ->
        error
    end
  end

  @doc """
  Get single prompt by number.
  """
  @spec get_prompt(config(), String.t()) :: {:ok, prompt()} | {:error, :not_found}
  def get_prompt(config, num) do
    case get_all_prompts(config) do
      {:ok, prompts} ->
        case Enum.find(prompts, &(&1.num == num)) do
          nil -> {:error, :not_found}
          prompt -> {:ok, prompt}
        end

      error ->
        error
    end
  end

  @doc """
  Apply CLI flag overrides to configuration.
  """
  @spec apply_overrides(config(), keyword()) :: config()
  def apply_overrides(config, opts) do
    config
    |> maybe_override(:project_dir, opts[:project_dir])
    |> maybe_override(:model, opts[:model])
    |> maybe_override(:log_mode, opts[:log_mode])
    |> maybe_override(:log_meta, opts[:log_meta])
    |> maybe_override(:events_mode, opts[:events_mode])
    |> apply_provider_override(opts[:provider])
    |> apply_repo_overrides(opts[:repo_override])
  end

  @doc """
  Parse commit messages file.
  """
  @spec parse_commit_messages(config()) :: {:ok, map()} | {:error, term()}
  def parse_commit_messages(config) do
    commit_file = config[:commit_messages_file] || config.commit_messages_file

    case File.read(commit_file) do
      {:ok, content} ->
        parse_commit_content(content)

      {:error, reason} ->
        {:error, {:file_not_found, commit_file, reason}}
    end
  end

  @doc """
  Validate phase_names mapping.
  """
  @spec validate_phase_names(config()) :: :ok
  def validate_phase_names(_config) do
    # Phase names are optional and validated by structure
    :ok
  end

  @doc """
  Validate events_mode value.
  """
  @spec validate_events_mode(config()) :: :ok | {:error, {:invalid_events_mode, String.t()}}
  def validate_events_mode(config) do
    case config[:events_mode] do
      nil ->
        :ok

      mode when mode in ["compact", "full", "off", :compact, :full, :off] ->
        :ok

      mode ->
        {:error, {:invalid_events_mode, mode}}
    end
  end

  @doc """
  Normalize events_mode to atom.
  """
  @spec normalize_events_mode(config()) :: config()
  def normalize_events_mode(config) do
    case config[:events_mode] do
      mode when is_binary(mode) ->
        Map.put(config, :events_mode, String.to_atom(String.downcase(mode)))

      _ ->
        config
    end
  end

  @doc """
  Validate prompt_overrides structure.
  """
  @spec validate_prompt_overrides(config()) :: :ok
  def validate_prompt_overrides(_config) do
    # Prompt overrides are optional and validated by structure
    :ok
  end

  @doc """
  Validate workspace_root and repo containment.
  """
  @spec validate_workspace_root(config()) ::
          :ok | {:error, {:repo_not_in_workspace, String.t()}}
  def validate_workspace_root(config) do
    case config[:workspace_root] do
      nil ->
        :ok

      workspace_root ->
        target_repos = config[:target_repos] || []

        invalid_repos =
          Enum.reject(target_repos, fn repo ->
            String.starts_with?(repo.path, workspace_root)
          end)

        case invalid_repos do
          [] ->
            :ok

          [repo | _] ->
            {:error, {:repo_not_in_workspace, repo.name}}
        end
    end
  end

  # Private helpers

  defp parse_prompt_line(line, config) do
    case String.split(line, "|") do
      [num, phase, sp, name, file, target_repos] ->
        %{
          num: String.trim(num),
          phase: String.to_integer(String.trim(phase)),
          sp: String.to_integer(String.trim(sp)),
          name: String.trim(name),
          file: String.trim(file),
          target_repos_raw: parse_target_repos_raw(target_repos),
          target_repos: expand_target_repos(target_repos, config)
        }

      [num, phase, sp, name, file] ->
        %{
          num: String.trim(num),
          phase: String.to_integer(String.trim(phase)),
          sp: String.to_integer(String.trim(sp)),
          name: String.trim(name),
          file: String.trim(file),
          target_repos_raw: nil,
          target_repos: nil
        }

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp parse_target_repos_raw(str) do
    str
    |> String.trim()
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> case do
      [] -> nil
      repos -> repos
    end
  end

  defp expand_target_repos(str, config) do
    case parse_target_repos_raw(str) do
      nil ->
        nil

      repos ->
        repo_groups = config[:repo_groups] || %{}

        Enum.flat_map(repos, fn repo ->
          case repo do
            "@" <> group_name ->
              Map.get(repo_groups, group_name, [])

            repo_name ->
              [repo_name]
          end
        end)
    end
  end

  defp parse_commit_content(content) do
    # Regex to match commit markers: === COMMIT NN === or === COMMIT NN:repo ===
    # Markers must be on their own line (start of line to end of line)
    marker_regex = ~r/^=== COMMIT (\d+)(?::([A-Za-z0-9._-]+))? ===$/m

    # Check for invalid repo names
    case validate_repo_names(content) do
      :ok ->
        parse_commits(content, marker_regex)

      error ->
        error
    end
  end

  defp validate_repo_names(content) do
    # Find all repo markers and validate repo names
    repo_marker_regex = ~r/^=== COMMIT \d+:(.+?) ===$/m

    invalid =
      Regex.scan(repo_marker_regex, content)
      |> Enum.reject(fn [_, repo_name] ->
        Regex.match?(~r/^[A-Za-z0-9._-]+$/, String.trim(repo_name))
      end)

    case invalid do
      [] -> :ok
      [[_, invalid_name] | _] -> {:error, {:invalid_repo_name, String.trim(invalid_name)}}
    end
  end

  defp parse_commits(content, marker_regex) do
    # Split content by actual marker lines (not escaped ones)
    lines = String.split(content, "\n")

    {messages, _current_key, _current_msg} =
      Enum.reduce(lines, {%{}, nil, []}, fn line, {acc, current_key, current_msg} ->
        cond do
          # Check if line is an exact marker (not escaped, no leading space)
          Regex.match?(marker_regex, line) ->
            # Save previous message if exists
            acc =
              if current_key do
                msg = current_msg |> Enum.reverse() |> Enum.join("\n") |> String.trim()
                Map.put(acc, current_key, msg)
              else
                acc
              end

            # Extract new marker info
            [[_, num, repo]] = Regex.scan(marker_regex, line)

            new_key =
              if repo && repo != "" do
                "#{num}:#{repo}"
              else
                num
              end

            {acc, new_key, []}

          # Line starts with backslash - treat as content (remove backslash)
          String.starts_with?(line, "\\") ->
            content_line = String.trim_leading(line, "\\")
            {acc, current_key, [content_line | current_msg]}

          # Any other line is content
          true ->
            {acc, current_key, [line | current_msg]}
        end
      end)

    # Don't forget the last message
    messages =
      if _current_key do
        msg = _current_msg |> Enum.reverse() |> Enum.join("\n") |> String.trim()
        Map.put(messages, _current_key, msg)
      else
        messages
      end

    {:ok, messages}
  end

  defp maybe_override(config, _key, nil), do: config

  defp maybe_override(config, key, value) do
    Map.put(config, key, value)
  end

  defp apply_provider_override(config, nil), do: config

  defp apply_provider_override(config, provider) when is_binary(provider) do
    Map.put(config, :provider, String.to_atom(provider))
  end

  defp apply_provider_override(config, provider) when is_atom(provider) do
    Map.put(config, :provider, provider)
  end

  defp apply_repo_overrides(config, nil), do: config
  defp apply_repo_overrides(config, []), do: config

  defp apply_repo_overrides(config, overrides) when is_list(overrides) do
    target_repos = config[:target_repos] || []

    updated_repos =
      Enum.map(target_repos, fn repo ->
        # Find override for this repo
        override =
          Enum.find_value(overrides, fn override_str ->
            case String.split(override_str, ":", parts: 2) do
              [name, path] when name == repo.name -> path
              _ -> nil
            end
          end)

        if override do
          Map.put(repo, :path, override)
        else
          repo
        end
      end)

    Map.put(config, :target_repos, updated_repos)
  end
end
