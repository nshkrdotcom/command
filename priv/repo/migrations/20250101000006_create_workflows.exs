defmodule Command.Repo.Migrations.CreateWorkflows do
  use Ecto.Migration

  def change do
    create table(:workflows, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Identity
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :version, :integer, default: 1, null: false

      # Status: draft, active, deprecated, archived
      add :status, :string, default: "draft", null: false

      # Is this a template that can be forked?
      add :is_template, :boolean, default: false, null: false
      add :forked_from_id, references(:workflows, type: :binary_id, on_delete: :nilify_all)

      # Step definitions - the actual workflow structure
      # Stored as JSONB for flexibility during development
      # Could be normalized to steps table later if needed
      add :steps, {:array, :map}, null: false, default: []
      # Example step:
      # %{
      #   id: "step_1",
      #   name: "Analyze Code",
      #   type: "agent_call",
      #   config: %{agent: "claude", model: "claude-sonnet-4-20250514", prompt_template: "..."},
      #   depends_on: [],
      #   approval_required: false,
      #   timeout_ms: 300000
      # }

      # Input schema - what parameters does this workflow accept?
      add :input_schema, :map, default: %{}
      # Example: %{pr_url: %{type: "string", required: true}}

      # Output schema - what does this workflow produce?
      add :output_schema, :map, default: %{}

      # Default configuration
      add :default_config, :map, default: %{}

      # Trigger configuration (for scheduled/automated runs)
      add :triggers, {:array, :map}, default: []
      # Example: [%{type: "schedule", cron: "0 9 * * *"}, %{type: "webhook", path: "/hooks/xyz"}]

      # Stats (denormalized)
      add :run_count, :integer, default: 0, null: false
      add :success_count, :integer, default: 0, null: false
      add :failure_count, :integer, default: 0, null: false
      add :avg_duration_ms, :bigint
      add :avg_cost_cents, :integer

      # Tags and categorization
      add :tags, {:array, :string}, default: []
      # "code_review", "refactor", "documentation", etc.
      add :category, :string

      # Metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:workflows, [:user_id])
    create index(:workflows, [:status])
    create unique_index(:workflows, [:user_id, :slug])
    create index(:workflows, [:is_template])
    create index(:workflows, [:tags], using: :gin)
    create index(:workflows, [:category])
  end
end
