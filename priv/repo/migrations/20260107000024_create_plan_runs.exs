defmodule Command.Repo.Migrations.CreatePlanRuns do
  use Ecto.Migration

  def change do
    create table(:plan_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false

      add :session_id, references(:sessions, type: :binary_id, on_delete: :nilify_all)

      add :plan_id, :binary_id
      add :plan_version, :string
      add :plan_hash, :string
      add :plan_ref, :string
      add :plan_data, :map, default: %{}
      add :status, :string, default: "queued", null: false
      add :runtime, :string
      add :runtime_ref, :string

      add :run_index_run_id,
          references(:runs, type: :binary_id, on_delete: :nilify_all, prefix: "run_index")

      add :trace_id,
          references(:traces, type: :binary_id, on_delete: :nilify_all, prefix: "lineage")

      add :work_id, :binary_id
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:plan_runs, [:user_id])
    create index(:plan_runs, [:session_id])
    create index(:plan_runs, [:plan_id])
    create index(:plan_runs, [:status])
    create index(:plan_runs, [:runtime])
    create index(:plan_runs, [:run_index_run_id])
    create index(:plan_runs, [:trace_id])
  end
end
