defmodule Command.Repo.Migrations.CreatePipelineTables do
  use Ecto.Migration

  def change do
    create table(:command_pipelines, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :status, :string, default: "active", null: false
      add :config, :map, default: %{}
      add :template_id, references(:workflows, type: :binary_id)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:command_pipelines, [:template_id])
    create index(:command_pipelines, [:status])

    create table(:command_pipeline_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :partition, :string, null: false
      add :status, :string, default: "pending", null: false
      add :flowstone_run_id, :string
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :result, :map
      add :error, :map
      add :pipeline_id, references(:command_pipelines, type: :binary_id), null: false
      add :session_id, references(:sessions, type: :binary_id)
      add :user_id, references(:users, type: :binary_id)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:command_pipeline_runs, [:pipeline_id, :status])
    create index(:command_pipeline_runs, [:session_id])
    create index(:command_pipeline_runs, [:flowstone_run_id])
    create index(:command_pipeline_runs, [:partition])

    create table(:command_pipeline_ai_operations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :asset_name, :string, null: false
      add :operation, :string, null: false
      add :provider, :string
      add :model, :string
      add :tokens_in, :integer, default: 0
      add :tokens_out, :integer, default: 0
      add :cost_usd, :decimal, precision: 10, scale: 6, default: 0
      add :duration_ms, :integer
      add :metadata, :map, default: %{}
      add :pipeline_run_id, references(:command_pipeline_runs, type: :binary_id), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:command_pipeline_ai_operations, [:pipeline_run_id])
    create index(:command_pipeline_ai_operations, [:asset_name])
    create index(:command_pipeline_ai_operations, [:provider, :model])
  end
end
