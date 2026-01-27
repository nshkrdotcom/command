defmodule Command.FlowStone.Resources.ArtifactStore do
  @moduledoc """
  Stores execution artifacts with run-scoped isolation.

  Artifacts are stored in the filesystem under:
    {log_dir}/{run_id}/{artifact_type}/{artifact_id}.{ext}

  Supported artifact types:
  - `:stream_log` - Text log of streaming output (.txt)
  - `:events_jsonl` - JSONL file of normalized events (.jsonl)
  - `:output` - Final output content (.txt)
  - `:metadata` - JSON metadata files (.json)

  ## Configuration

  Required config keys:
  - `:log_dir` - Base directory for artifact storage
  - `:run_id` - UUID of the run for isolation

  ## Example

      config = %{
        log_dir: "/var/log/flowstone",
        run_id: "550e8400-e29b-41d4-a716-446655440000"
      }

      {:ok, store} = ArtifactStore.setup(config)

      # Store a stream log
      artifact_spec = %{
        type: :stream_log,
        content: "Log output here...",
        prompt_num: "01"
      }
      {:ok, artifact_id} = ArtifactStore.store(store, artifact_spec)

      # Fetch it back
      {:ok, artifact} = ArtifactStore.fetch(store, artifact_id)

      # List all artifacts for the run
      {:ok, ids} = ArtifactStore.list(store)
  """

  use FlowStone.Resource

  require Logger

  @type artifact_type :: :stream_log | :events_jsonl | :output | :metadata

  @type t :: %{
          log_dir: String.t(),
          run_id: String.t(),
          run_dir: String.t()
        }

  @impl true
  def setup(config) do
    log_dir = config[:log_dir]
    run_id = config[:run_id]

    cond do
      is_nil(log_dir) ->
        {:error, :log_dir_required}

      is_nil(run_id) ->
        {:error, :run_id_required}

      true ->
        run_dir = Path.join(log_dir, run_id)

        case ensure_directory(run_dir) do
          :ok ->
            {:ok,
             %{
               log_dir: log_dir,
               run_id: run_id,
               run_dir: run_dir
             }}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @impl true
  def teardown(store) do
    flush(store)
    :ok
  end

  @impl true
  def health_check(store) do
    run_dir = store.run_dir

    case File.stat(run_dir) do
      {:ok, %File.Stat{access: access}} when access in [:read_write, :write] ->
        :healthy

      {:ok, %File.Stat{}} ->
        {:unhealthy, :directory_not_writable}

      {:error, reason} ->
        {:unhealthy, reason}
    end
  end

  @doc """
  Store an artifact to disk.

  Returns `{:ok, artifact_id}` on success, where artifact_id is a UUID.

  ## Parameters

  - `store` - The artifact store state
  - `artifact_spec` - Map with keys:
    - `:type` - Artifact type (`:stream_log`, `:events_jsonl`, `:output`, `:metadata`)
    - `:content` - String content to store
    - `:prompt_num` - Optional prompt number for metadata

  ## Example

      artifact_spec = %{
        type: :stream_log,
        content: "Agent output...",
        prompt_num: "05"
      }

      {:ok, artifact_id} = ArtifactStore.store(store, artifact_spec)
  """
  @spec store(t(), map()) :: {:ok, String.t()} | {:error, term()}
  def store(store, artifact_spec) do
    artifact_id = Ecto.UUID.generate()
    artifact_type = artifact_spec.type
    content = artifact_spec.content

    extension = extension_for_type(artifact_type)
    type_dir = Path.join(store.run_dir, Atom.to_string(artifact_type))

    with :ok <- ensure_directory(type_dir),
         artifact_path <- Path.join(type_dir, "#{artifact_id}#{extension}"),
         :ok <- File.write(artifact_path, content) do
      {:ok, artifact_id}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetch an artifact by ID.

  Returns `{:ok, artifact}` where artifact is a map with `:content` and `:type` keys.
  Returns `{:error, :not_found}` if the artifact doesn't exist.

  ## Example

      {:ok, artifact} = ArtifactStore.fetch(store, artifact_id)
      IO.puts(artifact.content)
  """
  @spec fetch(t(), String.t()) :: {:ok, map()} | {:error, term()}
  def fetch(store, artifact_id) do
    # Search for the artifact across all type directories
    artifact_types = [:stream_log, :events_jsonl, :output, :metadata]

    result =
      Enum.find_value(artifact_types, fn type ->
        extension = extension_for_type(type)
        type_dir = Path.join(store.run_dir, Atom.to_string(type))
        artifact_path = Path.join(type_dir, "#{artifact_id}#{extension}")

        case File.read(artifact_path) do
          {:ok, content} ->
            %{
              id: artifact_id,
              type: type,
              content: content
            }

          {:error, _} ->
            nil
        end
      end)

    case result do
      nil -> {:error, :not_found}
      artifact -> {:ok, artifact}
    end
  end

  @doc """
  List all artifact IDs for the current run.

  Returns `{:ok, [artifact_id]}`.

  ## Example

      {:ok, ids} = ArtifactStore.list(store)
      Enum.each(ids, fn id -> IO.puts("Artifact: #{id}") end)
  """
  @spec list(t()) :: {:ok, [String.t()]} | {:error, term()}
  def list(store) do
    artifact_types = [:stream_log, :events_jsonl, :output, :metadata]

    artifact_ids =
      Enum.flat_map(artifact_types, fn type ->
        type_dir = Path.join(store.run_dir, Atom.to_string(type))

        case File.ls(type_dir) do
          {:ok, files} ->
            extension = extension_for_type(type)

            files
            |> Enum.filter(&String.ends_with?(&1, extension))
            |> Enum.map(&String.replace_suffix(&1, extension, ""))

          {:error, _} ->
            []
        end
      end)

    {:ok, artifact_ids}
  end

  @doc """
  Ensure all pending writes are flushed to disk.

  Currently a no-op since we use synchronous File.write/2, but provided
  for future async implementations.
  """
  @spec flush(t()) :: :ok
  def flush(_store) do
    # No-op for synchronous writes
    # Future: If we implement async buffering, flush buffers here
    :ok
  end

  # Private helpers

  defp ensure_directory(path) do
    case File.mkdir_p(path) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp extension_for_type(:stream_log), do: ".txt"
  defp extension_for_type(:events_jsonl), do: ".jsonl"
  defp extension_for_type(:output), do: ".txt"
  defp extension_for_type(:metadata), do: ".json"
end
