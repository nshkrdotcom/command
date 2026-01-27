defmodule Command.Artifacts.PurgeWorker do
  @moduledoc """
  Background worker for hard-deleting expired artifacts after grace period.

  Runs weekly to permanently delete artifacts that have been soft-deleted
  for longer than the grace period (default: 30 days).

  ## Grace Period

  Soft-deleted artifacts are retained for a configurable grace period before
  permanent deletion. This allows recovery if artifacts were deleted in error.

  ## Usage

  Configure in config.exs:

      config :my_app, Oban,
        plugins: [
          {Oban.Plugins.Cron,
           crontab: [
             {"0 3 * * 0", Command.Artifacts.PurgeWorker}  # Weekly on Sunday at 3 AM
           ]}
        ]
  """

  import Ecto.Query
  alias Command.Artifacts.Artifact
  alias Command.Lineage.ProvenanceEdge
  alias Command.Repo

  @default_grace_period_days 30

  @doc """
  Perform hard deletion of expired artifacts.

  Artifacts that have been soft-deleted for longer than the grace period
  (default: #{@default_grace_period_days} days) are permanently deleted
  along with their associated provenance edges.

  Returns `{:ok, count}` where count is the number of hard-deleted artifacts.
  """
  @spec perform(keyword()) :: {:ok, non_neg_integer()}
  def perform(opts \\ []) do
    grace_days = Keyword.get(opts, :grace_period_days, @default_grace_period_days)
    cutoff = DateTime.add(DateTime.utc_now(), -grace_days * 86_400, :second)

    # Find artifacts eligible for hard delete
    artifact_ids =
      from(a in Artifact,
        where: not is_nil(a.deleted_at),
        where: a.deleted_at < ^cutoff,
        select: a.id
      )
      |> Repo.all()

    if Enum.empty?(artifact_ids) do
      {:ok, 0}
    else
      artifact_id_strings = Enum.map(artifact_ids, &to_string/1)

      # Delete associated provenance edges
      from(e in ProvenanceEdge,
        where: e.source_type == "artifact" and e.source_id in ^artifact_id_strings
      )
      |> Repo.delete_all()

      from(e in ProvenanceEdge,
        where: e.target_type == "artifact" and e.target_id in ^artifact_id_strings
      )
      |> Repo.delete_all()

      # Hard delete the artifact records
      {count, _} =
        from(a in Artifact,
          where: a.id in ^artifact_ids
        )
        |> Repo.delete_all()

      {:ok, count}
    end
  end
end
