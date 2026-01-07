defmodule Command.Repo.Migrations.CreateAiCosts do
  use Ecto.Migration

  def change do
    create table(:ai_costs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :session_id, references(:sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :workflow_id, :binary_id
      add :operation, :string, null: false
      add :provider, :string
      add :model, :string
      add :tokens_in, :integer, default: 0, null: false
      add :tokens_out, :integer, default: 0, null: false
      add :cost_usd, :decimal
      add :duration_ms, :integer
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:ai_costs, [:session_id])
    create index(:ai_costs, [:workflow_id])
    create index(:ai_costs, [:operation])
    create index(:ai_costs, [:provider])
    create index(:ai_costs, [:model])
  end
end
