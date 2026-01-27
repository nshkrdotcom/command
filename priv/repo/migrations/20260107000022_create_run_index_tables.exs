defmodule Command.Repo.Migrations.CreateRunIndexTables do
  use Ecto.Migration

  def change do
    execute "CREATE SCHEMA IF NOT EXISTS run_index",
            "DROP SCHEMA IF EXISTS run_index CASCADE"

    create table(:runs, primary_key: false, prefix: "run_index") do
      add :id, :uuid, primary_key: true
      add :root_run_id, :uuid
      add :parent_run_id, :uuid
      add :plan_id, :uuid
      add :plan_version, :text
      add :plan_hash, :text
      add :plan_ref, :text
      add :runtime, :text, null: false
      add :runtime_ref, :text, null: false
      add :status, :text, null: false
      add :status_reason, :text
      add :work_id, :uuid
      add :trace_id, :uuid
      add :session_id, :uuid
      add :actor_type, :text
      add :actor_id, :uuid
      add :tenant_id, :uuid
      add :inputs, :map
      add :output_artifact_refs, :map
      add :labels, :map
      add :cost_usd, :decimal, precision: 12, scale: 4
      add :usage, :map
      add :error_type, :text
      add :error_message, :text
      add :error_details, :map
      add :scheduled_at, :utc_datetime_usec
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:runs, [:runtime, :runtime_ref], prefix: "run_index")
    create index(:runs, [:trace_id], prefix: "run_index")
    create index(:runs, [:work_id], prefix: "run_index")
    create index(:runs, [:plan_id], prefix: "run_index")
    create index(:runs, [:parent_run_id], prefix: "run_index")
    create index(:runs, [:status], prefix: "run_index")
    create index(:runs, [:session_id], prefix: "run_index")

    create table(:steps, primary_key: false, prefix: "run_index") do
      add :id, :uuid, primary_key: true

      add :run_id,
          references(:runs, type: :uuid, on_delete: :delete_all, prefix: "run_index"),
          null: false

      add :step_id, :uuid
      add :step_key, :text, null: false
      add :action_name, :text, null: false
      add :action_module, :text
      add :tool_name, :text
      add :status, :text, null: false
      add :status_reason, :text
      add :work_id, :uuid
      add :trace_id, :uuid
      add :span_id, :uuid
      add :attempt, :integer, default: 1, null: false
      add :max_attempts, :integer
      add :queue, :text
      add :inputs, :map
      add :output_artifact_refs, :map
      add :cost_usd, :decimal, precision: 12, scale: 4
      add :usage, :map
      add :error_type, :text
      add :error_message, :text
      add :error_details, :map
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:steps, [:run_id, :step_key], prefix: "run_index")
    create index(:steps, [:run_id], prefix: "run_index")
    create index(:steps, [:span_id], prefix: "run_index")
    create index(:steps, [:work_id], prefix: "run_index")
    create index(:steps, [:status], prefix: "run_index")
  end
end
