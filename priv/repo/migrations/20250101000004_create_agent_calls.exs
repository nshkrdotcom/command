defmodule Command.Repo.Migrations.CreateAgentCalls do
  use Ecto.Migration

  def change do
    create table(:agent_calls, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :session_id, references(:sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Which agent/model
      # "anthropic", "openai", "google"
      add :provider, :string, null: false
      # "claude-sonnet-4-20250514", "gpt-4o", etc.
      add :model, :string, null: false

      # Status: pending, streaming, completed, failed, cancelled, timeout
      add :status, :string, default: "pending", null: false

      # The actual prompt sent (may be large, stored separately if needed)
      # Full messages array
      add :prompt_messages, {:array, :map}, null: false
      add :system_prompt, :text

      # Response
      add :response_content, :text
      # For structured responses
      add :response_blocks, {:array, :map}, default: []
      # "end_turn", "tool_use", "max_tokens", etc.
      add :stop_reason, :string

      # Tokens and cost
      add :tokens_in, :integer
      add :tokens_out, :integer
      add :cache_tokens_read, :integer, default: 0
      add :cache_tokens_write, :integer, default: 0
      # Calculated cost in cents
      add :cost_cents, :integer

      # Timing
      add :started_at, :utc_datetime_usec
      # Time to first token
      add :first_token_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :duration_ms, :integer

      # Request configuration
      add :temperature, :float
      add :max_tokens, :integer
      # Names of tools available
      add :tools_provided, {:array, :string}, default: []

      # Error tracking
      add :error_type, :string
      add :error_message, :text
      add :retry_count, :integer, default: 0

      # If part of a workflow
      add :workflow_run_id, :binary_id
      add :workflow_step_id, :binary_id

      # Metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:agent_calls, [:session_id])
    create index(:agent_calls, [:user_id])
    create index(:agent_calls, [:status])
    create index(:agent_calls, [:provider, :model])
    create index(:agent_calls, [:workflow_run_id])
    create index(:agent_calls, [:inserted_at])

    # For cost reporting
    create index(:agent_calls, [:user_id, :inserted_at])
  end
end
