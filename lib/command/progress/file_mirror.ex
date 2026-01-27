defmodule Command.Progress.FileMirror do
  @moduledoc """
  File-based progress mirroring for compatibility with the legacy
  progress tracking format.

  Mirrors database progress state to a plain text file for:
  - Compatibility with existing scripts that read progress files
  - Standalone execution without database (--file-only mode)
  - Human-readable progress inspection

  ## File Format

  Each line represents one prompt's progress:

      num:status:timestamp:commit_info

  Where commit_info is either:
  - A commit hash (e.g., `abc123def`)
  - `no_changes` if no changes were made
  - `no_commit` if --no-commit was used
  - Empty string for failed/pending

  For multi-repo prompts, commit_info contains repo=hash pairs:

      02:completed:2026-01-26T12:00:00Z:command=abc123,flowstone=def456
  """

  @doc """
  Sync a single prompt state entry to the progress file.

  Appends or updates the entry for the given prompt number.
  """
  @spec sync_to_file(String.t(), String.t(), map()) :: :ok | {:error, term()}
  def sync_to_file(path, num, entry) do
    line = format_entry(num, entry)

    case File.exists?(path) do
      true ->
        # Read existing, replace or append
        content = File.read!(path)
        lines = String.split(content, "\n", trim: true)
        prefix = "#{num}:"

        updated =
          if Enum.any?(lines, &String.starts_with?(&1, prefix)) do
            Enum.map(lines, fn l ->
              if String.starts_with?(l, prefix), do: line, else: l
            end)
          else
            lines ++ [line]
          end

        File.write!(path, Enum.join(updated, "\n") <> "\n")
        :ok

      false ->
        File.write!(path, line <> "\n")
        :ok
    end
  end

  @doc """
  Rewrite the entire progress file from a state map.

  The state map is keyed by prompt number.
  """
  @spec sync_all(String.t(), map()) :: :ok | {:error, term()}
  def sync_all(path, states) do
    lines =
      states
      |> Enum.sort_by(fn {num, _} -> num end)
      |> Enum.map(fn {num, entry} -> format_entry(num, entry) end)

    File.write!(path, Enum.join(lines, "\n") <> "\n")
    :ok
  end

  @doc """
  Read and parse an existing progress file.

  Returns `{:ok, entries}` or `{:error, reason}`.
  """
  @spec read(String.t()) :: {:ok, [map()]} | {:error, term()}
  def read(path) do
    case File.read(path) do
      {:ok, content} ->
        entries =
          content
          |> String.split("\n", trim: true)
          |> Enum.reject(&(String.trim(&1) == ""))
          |> Enum.map(&parse_line/1)
          |> Enum.reject(&is_nil/1)

        {:ok, entries}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Append a single entry to the progress file.
  """
  @spec append(String.t(), String.t(), atom(), map()) :: :ok | {:error, term()}
  def append(path, num, status, opts \\ %{}) do
    timestamp = opts[:timestamp] || DateTime.utc_now()
    commit_info = format_commit_info(opts)

    line = "#{num}:#{status}:#{DateTime.to_iso8601(timestamp)}:#{commit_info}"

    File.write!(path, line <> "\n", [:append])
    :ok
  end

  # Private helpers

  defp format_entry(num, entry) do
    timestamp = format_timestamp(entry[:timestamp])
    status = entry[:status] || :pending
    commit_info = format_entry_commit_info(entry)

    "#{num}:#{status}:#{timestamp}:#{commit_info}"
  end

  defp format_entry_commit_info(%{repos: repos}) when is_list(repos) do
    repos
    |> Enum.map(fn repo ->
      hash = repo[:commit_hash] || to_string(repo[:status] || "")
      "#{repo.repo}=#{hash}"
    end)
    |> Enum.join(",")
  end

  defp format_entry_commit_info(%{commit_hash: hash}) when is_binary(hash) and hash != "" do
    hash
  end

  defp format_entry_commit_info(%{commit_status: status}) when not is_nil(status) do
    to_string(status)
  end

  defp format_entry_commit_info(_), do: ""

  defp format_timestamp(nil), do: DateTime.to_iso8601(DateTime.utc_now())
  defp format_timestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_timestamp(other), do: to_string(other)

  defp format_commit_info(%{commit_hash: hash}) when is_binary(hash) and hash != "" do
    hash
  end

  defp format_commit_info(%{commit_status: status}) when not is_nil(status) do
    to_string(status)
  end

  defp format_commit_info(_), do: ""

  defp parse_line(line) do
    # Format: num:status:ISO8601_timestamp:commit_info
    # ISO8601 timestamps contain colons, so we split by first two colons,
    # then the rest is timestamp:commit_info
    case String.split(line, ":", parts: 3) do
      [num, status, rest] ->
        # rest is like "2026-01-26T12:00:00Z:abc123" or "2026-01-26T12:00:00Z:"
        # Find the last colon-delimited segment that could be commit info
        # ISO8601 always ends with Z or +HH:MM, so split after the timestamp
        {timestamp, commit_info} = split_timestamp_and_commit(rest)

        %{
          num: num,
          status: status,
          timestamp: timestamp,
          commit_hash: parse_commit_hash(commit_info)
        }

      _ ->
        nil
    end
  end

  # Split "2026-01-26T12:00:00Z:abc123" into {"2026-01-26T12:00:00Z", "abc123"}
  # or "2026-01-26T12:00:00Z:" into {"2026-01-26T12:00:00Z", ""}
  defp split_timestamp_and_commit(rest) do
    # ISO8601 timestamps match: YYYY-MM-DDTHH:MM:SSZ (or with offset)
    # Match the full timestamp pattern greedily, then take remainder as commit info
    case Regex.run(~r/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[^\:]*):(.*)$/, rest) do
      [_, timestamp, commit_info] ->
        {timestamp, commit_info}

      nil ->
        # No commit info after timestamp
        {rest, ""}
    end
  end

  defp parse_commit_hash(""), do: nil
  defp parse_commit_hash("no_changes"), do: nil
  defp parse_commit_hash("no_commit"), do: nil
  defp parse_commit_hash(hash), do: hash
end
