defmodule Command.CLI.LegacyAdapter do
  @moduledoc """
  Compatibility adapter for converting legacy run_prompts.exs format
  to the Command PromptSet structure.

  The legacy format uses:
  - A config .exs file that returns a map
  - A prompts.txt file with pipe-delimited fields
  - A commit-messages.txt file with marker-delimited sections

  This adapter loads and converts these formats to the PromptSet-compatible
  structure used by the CLI execution surface.
  """

  alias Command.CLI.ConfigLoader

  @doc """
  Load a legacy config file and convert it to a PromptSet-compatible map.

  Returns `{:ok, prompt_set}` or `{:error, reason}`.
  """
  @spec load_legacy_config(String.t()) :: {:ok, map()} | {:error, term()}
  def load_legacy_config(path) do
    with {:ok, config} <- ConfigLoader.load(path),
         :ok <- ConfigLoader.validate(config),
         {:ok, prompt_set} <- to_prompt_set(config) do
      {:ok, prompt_set}
    end
  end

  @doc """
  Parse a single prompts.txt line into a prompt map.

  Returns `{:ok, prompt}`, `:skip` for comments/blank lines,
  or `{:error, {:malformed_prompt_line, line}}`.
  """
  @spec parse_prompt_line(String.t(), map()) :: {:ok, map()} | :skip | {:error, term()}
  def parse_prompt_line(line, repo_groups \\ %{}) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        {:error, {:malformed_prompt_line, line}}

      String.starts_with?(trimmed, "#") ->
        :skip

      true ->
        do_parse_prompt_line(trimmed, repo_groups)
    end
  end

  @doc """
  Parse commit messages file content.

  Returns `{:ok, messages_map}` or `{:error, reason}`.
  """
  @spec parse_commit_messages(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_commit_messages(content) do
    # Delegate to ConfigLoader's internal parsing logic by constructing
    # a temporary config and calling parse_commit_messages
    # We replicate the logic here to avoid circular deps
    marker_regex = ~r/^=== COMMIT (\d+)(?::([A-Za-z0-9._-]+))? ===$/m

    # Check for invalid repo names
    repo_marker_regex = ~r/^=== COMMIT \d+:(.+?) ===$/m

    invalid =
      Regex.scan(repo_marker_regex, content)
      |> Enum.reject(fn [_, repo_name] ->
        Regex.match?(~r/^[A-Za-z0-9._-]+$/, String.trim(repo_name))
      end)

    case invalid do
      [] ->
        parse_commits(content, marker_regex)

      [[_, invalid_name] | _] ->
        {:error, {:invalid_repo_name, String.trim(invalid_name)}}
    end
  end

  @doc """
  Convert a legacy config map to a PromptSet-compatible map.

  Reads the prompts and commit messages files referenced in the config,
  then builds a PromptSet structure with all fields populated.
  """
  @spec to_prompt_set(map()) :: {:ok, map()} | {:error, term()}
  def to_prompt_set(config) do
    repo_groups = config[:repo_groups] || %{}

    with {:ok, prompts} <- read_prompts(config, repo_groups),
         {:ok, commit_messages} <- read_commit_messages(config) do
      slug = generate_slug(config)

      prompt_set = %{
        name: config[:name] || "Legacy Config #{slug}",
        slug: slug,
        prompts: prompts,
        commit_messages: commit_messages,
        phase_names: normalize_phase_names(config[:phase_names]),
        config: build_config(config),
        status: "active"
      }

      {:ok, prompt_set}
    end
  end

  # Private helpers

  defp do_parse_prompt_line(line, repo_groups) do
    case String.split(line, "|") do
      [num, phase, sp, name, file, target_repos] ->
        raw_repos = parse_target_repos_raw(target_repos)
        expanded = expand_target_repos(raw_repos, repo_groups)

        {:ok,
         %{
           num: String.trim(num),
           phase: String.to_integer(String.trim(phase)),
           sp: String.to_integer(String.trim(sp)),
           name: String.trim(name),
           file: String.trim(file),
           target_repos_raw: raw_repos,
           target_repos: expanded
         }}

      [num, phase, sp, name, file] ->
        {:ok,
         %{
           num: String.trim(num),
           phase: String.to_integer(String.trim(phase)),
           sp: String.to_integer(String.trim(sp)),
           name: String.trim(name),
           file: String.trim(file),
           target_repos_raw: nil,
           target_repos: nil
         }}

      _ ->
        {:error, {:malformed_prompt_line, line}}
    end
  rescue
    _ -> {:error, {:malformed_prompt_line, line}}
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

  defp expand_target_repos(nil, _repo_groups), do: nil

  defp expand_target_repos(repos, repo_groups) do
    Enum.flat_map(repos, fn repo ->
      case repo do
        "@" <> group_name ->
          Map.get(repo_groups, group_name, [])

        repo_name ->
          [repo_name]
      end
    end)
  end

  defp read_prompts(config, repo_groups) do
    prompts_file = config[:prompts_file]

    case File.read(prompts_file) do
      {:ok, content} ->
        results =
          content
          |> String.split("\n", trim: true)
          |> Enum.map(&parse_prompt_line(&1, repo_groups))
          |> Enum.reject(&(&1 == :skip))

        errors = Enum.filter(results, &match?({:error, _}, &1))

        case errors do
          [] ->
            prompts = Enum.map(results, fn {:ok, p} -> prompt_to_json(p) end)
            {:ok, prompts}

          [{:error, reason} | _] ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, {:file_not_found, prompts_file, reason}}
    end
  end

  defp read_commit_messages(config) do
    commit_file = config[:commit_messages_file]

    case File.read(commit_file) do
      {:ok, content} ->
        parse_commit_messages(content)

      {:error, reason} ->
        {:error, {:file_not_found, commit_file, reason}}
    end
  end

  defp prompt_to_json(prompt) do
    base = %{
      "num" => prompt.num,
      "phase" => prompt.phase,
      "sp" => prompt.sp,
      "name" => prompt.name,
      "file" => prompt.file
    }

    if prompt.target_repos do
      Map.put(base, "target_repos", prompt.target_repos)
    else
      base
    end
  end

  defp build_config(config) do
    %{
      project_dir: config[:project_dir],
      target_repos: config[:target_repos],
      repo_groups: config[:repo_groups],
      prompts_file: config[:prompts_file],
      commit_messages_file: config[:commit_messages_file],
      progress_file: config[:progress_file],
      log_dir: config[:log_dir],
      default_model: config[:model],
      default_provider: to_string(config[:provider] || :claude),
      allowed_tools: config[:allowed_tools] || [],
      permission_mode: config[:permission_mode],
      log_mode: config[:log_mode],
      log_meta: config[:log_meta],
      events_mode: config[:events_mode],
      workspace_root: config[:workspace_root],
      db_enabled: config[:db_enabled],
      file_mirror: config[:file_mirror]
    }
  end

  defp normalize_phase_names(nil), do: %{}

  defp normalize_phase_names(phase_names) when is_map(phase_names) do
    Map.new(phase_names, fn {k, v} -> {to_string(k), v} end)
  end

  defp generate_slug(config) do
    base =
      config[:name] ||
        config[:project_dir] ||
        "legacy-config"

    base
    |> Path.basename()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9-]/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
    |> then(&"#{&1}-#{:erlang.phash2(config, 65536)}")
  end

  defp parse_commits(content, marker_regex) do
    lines = String.split(content, "\n")

    {messages, current_key, current_msg} =
      Enum.reduce(lines, {%{}, nil, []}, fn line, {acc, current_key, current_msg} ->
        cond do
          Regex.match?(marker_regex, line) ->
            acc =
              if current_key do
                msg = current_msg |> Enum.reverse() |> Enum.join("\n") |> String.trim()
                Map.put(acc, current_key, msg)
              else
                acc
              end

            new_key =
              case Regex.scan(marker_regex, line) do
                [[_, num, repo]] when repo != "" ->
                  "#{num}:#{repo}"

                [[_, num | _]] ->
                  num
              end

            {acc, new_key, []}

          String.starts_with?(line, "\\") ->
            content_line = String.trim_leading(line, "\\")
            {acc, current_key, [content_line | current_msg]}

          true ->
            {acc, current_key, [line | current_msg]}
        end
      end)

    messages =
      if current_key do
        msg = current_msg |> Enum.reverse() |> Enum.join("\n") |> String.trim()
        Map.put(messages, current_key, msg)
      else
        messages
      end

    {:ok, messages}
  end
end
