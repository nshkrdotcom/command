defmodule Command.Repo.Migrations.CreateArtifactsTable do
  use Ecto.Migration

  def change do
    create table(:artifacts, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :run_id, :uuid, null: false
      add :step_id, :uuid
      add :prompt_num, :varchar, size: 10
      add :type, :varchar, size: 50, null: false
      add :path, :varchar, size: 500, null: false
      add :content_hash, :varchar, size: 64
      add :size_bytes, :bigint
      add :metadata, :jsonb, default: "{}", null: false
      add :verified_at, :utc_datetime_usec
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:artifacts, [:run_id])
    create index(:artifacts, [:type])
    create index(:artifacts, [:content_hash])
    create index(:artifacts, [:run_id, :prompt_num])
    create index(:artifacts, [:deleted_at])
  end
end
