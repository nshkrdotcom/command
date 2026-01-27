defmodule Command.Artifacts.CasGcWorker do
  @moduledoc """
  Background worker for garbage collecting unreferenced CAS content.

  Runs weekly (after PurgeWorker) to remove content files that are no longer
  referenced by any active artifacts.

  ## Algorithm

  1. Query all content hashes referenced by active artifacts
  2. Walk the `artifacts/content/` directory tree
  3. Delete any files whose hash is not in the referenced set
  4. Prune empty hash-prefix directories

  ## Usage

  Configure in config.exs:

      config :my_app, Oban,
        plugins: [
          {Oban.Plugins.Cron,
           crontab: [
             {"0 4 * * 0", Command.Artifacts.CasGcWorker}  # Weekly on Sunday at 4 AM
           ]}
        ]
  """

  import Ecto.Query
  alias Command.Artifacts.Artifact
  alias Command.Repo

  @doc """
  Perform CAS garbage collection.

  1. Queries all content hashes referenced by active (non-deleted) artifacts
  2. Walks the `artifacts/content/` directory tree
  3. Deletes any files whose hash is not in the referenced set
  4. Prunes empty hash-prefix directories

  Returns `{:ok, count}` where count is the number of removed files.
  """
  @spec perform() :: {:ok, non_neg_integer()}
  def perform do
    artifacts_root = Application.get_env(:command, :artifacts_root, "artifacts")
    content_dir = Path.join(artifacts_root, "content")

    # Step 1: Get all referenced content hashes
    referenced_hashes =
      from(a in Artifact,
        where: is_nil(a.deleted_at) and not is_nil(a.content_hash),
        select: a.content_hash,
        distinct: true
      )
      |> Repo.all()
      |> MapSet.new()

    # Step 2: Walk content directory and delete unreferenced files
    count =
      if File.dir?(content_dir) do
        content_dir
        |> File.ls!()
        |> Enum.reduce(0, fn prefix_dir, acc ->
          acc + gc_prefix_dir(Path.join(content_dir, prefix_dir), referenced_hashes)
        end)
      else
        0
      end

    {:ok, count}
  end

  defp gc_prefix_dir(prefix_path, referenced_hashes) do
    if File.dir?(prefix_path) do
      deleted = gc_hash_files(prefix_path, referenced_hashes)
      prune_empty_dir(prefix_path)
      deleted
    else
      0
    end
  end

  defp gc_hash_files(prefix_path, referenced_hashes) do
    prefix_path
    |> File.ls!()
    |> Enum.reduce(0, fn hash_file, acc ->
      if MapSet.member?(referenced_hashes, hash_file) do
        acc
      else
        File.rm!(Path.join(prefix_path, hash_file))
        acc + 1
      end
    end)
  end

  defp prune_empty_dir(path) do
    case File.ls!(path) do
      [] -> File.rmdir(path)
      _ -> :ok
    end
  end
end
