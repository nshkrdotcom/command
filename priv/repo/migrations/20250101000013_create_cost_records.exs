defmodule Command.Repo.Migrations.CreateCostRecords do
  use Ecto.Migration

  def change do
    create table(:cost_records, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # What incurred this cost?
      # "agent_call", "embedding", "tool_execution"
      add :source_type, :string, null: false
      add :source_id, :binary_id, null: false

      # Context
      add :session_id, references(:sessions, type: :binary_id, on_delete: :nilify_all)
      add :workflow_run_id, :binary_id

      # Provider and service
      # "anthropic", "openai", "google", "cohere"
      add :provider, :string, null: false
      # "chat", "embedding", "image", "speech"
      add :service, :string, null: false
      add :model, :string, null: false

      # Usage
      add :tokens_in, :integer, default: 0
      add :tokens_out, :integer, default: 0
      add :cache_tokens_read, :integer, default: 0
      add :cache_tokens_write, :integer, default: 0

      # For non-token-based pricing
      # e.g., image count, audio seconds
      add :units, :decimal
      add :unit_type, :string

      # Cost calculation
      # Actual cost in cents
      add :cost_cents, :integer, null: false
      # Price used for calculation (in cents per 1M)
      add :price_per_million_in, :integer
      add :price_per_million_out, :integer

      # Timing
      add :incurred_at, :utc_datetime_usec, null: false

      # Daily aggregation bucket (for efficient queries)
      add :day, :date, null: false

      # Metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:cost_records, [:user_id])
    create index(:cost_records, [:user_id, :day])
    create index(:cost_records, [:session_id])
    create index(:cost_records, [:source_type, :source_id])
    create index(:cost_records, [:provider, :model])
    create index(:cost_records, [:incurred_at])

    # Daily cost summary table for fast reporting
    create table(:cost_daily_summaries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :day, :date, null: false

      # Aggregated stats
      add :total_cost_cents, :integer, default: 0, null: false
      add :total_tokens_in, :bigint, default: 0
      add :total_tokens_out, :bigint, default: 0
      add :total_requests, :integer, default: 0

      # Breakdown by provider
      add :cost_by_provider, :map, default: %{}
      # Example: %{"anthropic" => 1500, "openai" => 300}

      # Breakdown by model
      add :cost_by_model, :map, default: %{}

      # Breakdown by session
      add :cost_by_session, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:cost_daily_summaries, [:user_id, :day])
    create index(:cost_daily_summaries, [:user_id, :day, :total_cost_cents])
  end
end
