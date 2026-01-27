defmodule Command.Artifacts.RetentionWorker do
  @moduledoc """
  Background worker for soft-deleting expired artifacts.

  Runs daily to identify artifacts that have exceeded their retention period
  and marks them as soft-deleted (sets deleted_at timestamp).

  ## Retention Policy

  Artifacts are expired based on their type's retention_days:
  - Prompts: indefinite
  - Responses: 365 days
  - Transcripts: 90 days
  - Diffs: 365 days
  - etc.

  Artifacts with provenance edges of type `released_in`, `implements`, or
  related to approvals are **pinned** and excluded from automatic deletion.

  ## Usage

  If using Oban:

      defmodule MyApp.Application do
        def start(_type, _args) do
          children = [
            {Oban, oban_config()},
            # ...
          ]
        end

        defp oban_config do
          Application.fetch_env!(:my_app, Oban)
        end
      end

  Configure in config.exs:

      config :my_app, Oban,
        repo: MyApp.Repo,
        plugins: [
          {Oban.Plugins.Cron,
           crontab: [
             {"0 2 * * *", Command.Artifacts.RetentionWorker}  # Daily at 2 AM
           ]}
        ],
        queues: [artifacts: 10]
  """

  import Ecto.Query
  alias Command.Artifacts.Artifact
  alias Command.Lineage.ProvenanceEdge
  alias Command.Repo

  @retention_days_by_type %{
    "stream_log" => 90,
    "transcript" => 90,
    "events" => 90,
    "diff" => 365,
    "response" => 365,
    "input" => 365,
    "output" => 365,
    "manifest" => 365,
    "progress" => 365,
    "cost" => 365,
    "telemetry" => 365
  }

  @pinning_relationships ~w(released_in implements)

  @doc """
  Perform retention cleanup (soft delete expired artifacts).

  Queries artifacts past their retention period, excludes pinned artifacts,
  and marks them as soft-deleted by setting `deleted_at`.

  Returns `{:ok, count}` where count is the number of soft-deleted artifacts.
  """
  @spec perform() :: {:ok, non_neg_integer()}
  def perform do
    now = DateTime.utc_now()
    pinned_ids = pinned_artifact_ids()

    count =
      @retention_days_by_type
      |> Enum.reduce(0, fn {type, days}, acc ->
        cutoff = DateTime.add(now, -days * 86_400, :second)

        {updated, _} =
          from(a in Artifact,
            where: a.artifact_type == ^type,
            where: a.inserted_at < ^cutoff,
            where: is_nil(a.deleted_at),
            where: a.id not in ^pinned_ids
          )
          |> Repo.update_all(set: [deleted_at: now])

        acc + updated
      end)

    {:ok, count}
  end

  @doc """
  Returns the list of artifact IDs that are pinned via provenance edges.

  Pinned artifacts have provenance edges with `released_in` or `implements`
  relationships and are excluded from automatic retention deletion.
  """
  @spec pinned_artifact_ids() :: [String.t()]
  def pinned_artifact_ids do
    from(e in ProvenanceEdge,
      where: e.source_type == "artifact" and e.relationship in ^@pinning_relationships,
      select: e.source_id,
      distinct: true
    )
    |> Repo.all()
  end
end
