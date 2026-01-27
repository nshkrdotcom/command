defmodule Command.Repo.Migrations.AddProvenanceColumnsToArtifacts do
  use Ecto.Migration

  def change do
    alter table(:artifacts) do
      add :run_id, :uuid
      add :step_id, :uuid
      add :prompt_num, :string, size: 10
      add :content_hash, :string, size: 64
      add :verified_at, :utc_datetime_usec
      add :deleted_at, :utc_datetime_usec
    end

    create index(:artifacts, [:run_id], where: "run_id IS NOT NULL")
    create index(:artifacts, [:content_hash], where: "content_hash IS NOT NULL")

    create index(:artifacts, [:run_id, :prompt_num],
             where: "run_id IS NOT NULL AND prompt_num IS NOT NULL"
           )

    create index(:artifacts, [:deleted_at], where: "deleted_at IS NOT NULL")
  end
end
