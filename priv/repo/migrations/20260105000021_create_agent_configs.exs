defmodule Command.Repo.Migrations.CreateAgentConfigs do
  use Ecto.Migration

  def change do
    create table(:command_agent_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agent_id, :string, null: false
      add :type, :string, null: false
      add :status, :string, default: "active", null: false
      add :config, :map, default: %{}
      add :signals, :map, default: %{}
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:command_agent_configs, [:agent_id])
    create index(:command_agent_configs, [:status])
    create index(:command_agent_configs, [:type])

    create table(:command_agent_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, default: "pending", null: false
      add :signal_type, :string
      add :signal_id, :string
      add :input, :map, default: %{}
      add :output, :map, default: %{}
      add :error, :map
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :duration_ms, :integer
      add :metadata, :map, default: %{}
      add :agent_config_id, references(:command_agent_configs, type: :binary_id), null: false
      add :session_id, references(:sessions, type: :binary_id)
      add :user_id, references(:users, type: :binary_id)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:command_agent_sessions, [:agent_config_id])
    create index(:command_agent_sessions, [:session_id])
    create index(:command_agent_sessions, [:status])
  end
end
