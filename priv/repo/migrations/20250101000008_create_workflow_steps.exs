defmodule Command.Repo.Migrations.CreateWorkflowSteps do
  use Ecto.Migration

  def change do
    create table(:workflow_steps, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workflow_run_id, references(:workflow_runs, type: :binary_id, on_delete: :delete_all),
        null: false

      # Step identification (matches step.id in workflow definition)
      add :step_id, :string, null: false
      add :step_name, :string, null: false
      # "agent_call", "rag_query", "shell", "approval", "python", etc.
      add :step_type, :string, null: false

      # Snapshot of step config at execution time
      add :step_config, :map, null: false

      # Status: pending, running, waiting_approval, completed, failed, skipped, timeout
      add :status, :string, default: "pending", null: false

      # Input to this step (may come from previous steps or workflow input)
      add :input, :map, default: %{}

      # Output from this step
      add :output, :map, default: %{}

      # If this step is an agent call, link it
      add :agent_call_id, references(:agent_calls, type: :binary_id, on_delete: :nilify_all)

      # If this step requires approval
      # Link to approval_items
      add :approval_id, :binary_id

      # Timing
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :duration_ms, :integer

      # Cost (if applicable)
      add :tokens_in, :integer
      add :tokens_out, :integer
      add :cost_cents, :integer

      # Error tracking
      add :error_type, :string
      add :error_message, :text

      # Retry tracking within the step
      add :attempt_number, :integer, default: 1
      add :max_attempts, :integer, default: 1

      # Execution order
      add :sequence, :integer, null: false

      # Dependencies (which step_ids must complete before this runs)
      add :depends_on, {:array, :string}, default: []

      # Metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:workflow_steps, [:workflow_run_id, :sequence])
    create index(:workflow_steps, [:workflow_run_id, :step_id])
    create index(:workflow_steps, [:status])
    create index(:workflow_steps, [:agent_call_id])
  end
end
