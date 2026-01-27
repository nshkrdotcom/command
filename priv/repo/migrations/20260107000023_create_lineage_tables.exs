defmodule Command.Repo.Migrations.CreateLineageTables do
  use Ecto.Migration

  def change do
    execute "CREATE SCHEMA IF NOT EXISTS lineage",
            "DROP SCHEMA IF EXISTS lineage CASCADE"

    create table(:traces, primary_key: false, prefix: "lineage") do
      add :id, :uuid, primary_key: true
      add :root_trace_id, :uuid
      add :parent_trace_id, :uuid
      add :run_id, :uuid
      add :work_id, :uuid
      add :origin, :text
      add :origin_ref, :text
      add :status, :text
      add :attributes, :map
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:traces, [:run_id], prefix: "lineage")
    create index(:traces, [:work_id], prefix: "lineage")

    create table(:spans, primary_key: false, prefix: "lineage") do
      add :id, :uuid, primary_key: true

      add :trace_id,
          references(:traces, type: :uuid, on_delete: :delete_all, prefix: "lineage"),
          null: false

      add :parent_span_id, :uuid
      add :run_id, :uuid
      add :step_id, :uuid
      add :work_id, :uuid
      add :name, :text, null: false
      add :kind, :text
      add :status, :text
      add :attributes, :map
      add :metrics, :map
      add :error_type, :text
      add :error_message, :text
      add :error_details, :map
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:spans, [:trace_id], prefix: "lineage")
    create index(:spans, [:run_id], prefix: "lineage")
    create index(:spans, [:step_id], prefix: "lineage")
    create index(:spans, [:work_id], prefix: "lineage")

    create table(:artifacts, primary_key: false, prefix: "lineage") do
      add :id, :uuid, primary_key: true
      add :trace_id, :uuid

      add :span_id,
          references(:spans, type: :uuid, on_delete: :nilify_all, prefix: "lineage")

      add :run_id, :uuid
      add :step_id, :uuid
      add :type, :text, null: false
      add :uri, :text
      add :checksum, :text
      add :size_bytes, :bigint
      add :mime_type, :text
      add :metadata, :map
      add :created_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:artifacts, [:trace_id], prefix: "lineage")
    create index(:artifacts, [:span_id], prefix: "lineage")
    create index(:artifacts, [:run_id], prefix: "lineage")

    create table(:edges, primary_key: false, prefix: "lineage") do
      add :id, :uuid, primary_key: true
      add :trace_id, :uuid
      add :source_type, :text, null: false
      add :source_id, :uuid, null: false
      add :target_type, :text, null: false
      add :target_id, :uuid, null: false
      add :relationship, :text, null: false
      add :metadata, :map

      timestamps(type: :utc_datetime_usec)
    end

    create index(:edges, [:trace_id], prefix: "lineage")
    create index(:edges, [:source_type, :source_id], prefix: "lineage")
    create index(:edges, [:target_type, :target_id], prefix: "lineage")

    create table(:events, primary_key: false, prefix: "lineage") do
      add :id, :uuid, primary_key: true
      add :trace_id, :uuid
      add :span_id, :uuid
      add :event_type, :text, null: false
      add :occurred_at, :utc_datetime_usec, null: false
      add :source, :text
      add :source_ref, :text
      add :payload, :map

      timestamps(type: :utc_datetime_usec)
    end

    create index(:events, [:trace_id], prefix: "lineage")
    create index(:events, [:span_id], prefix: "lineage")
    create index(:events, [:event_type], prefix: "lineage")
  end
end
