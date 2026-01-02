defmodule Command.Workflows.WorkflowStep do
  @moduledoc """
  Schema for individual workflow step executions.

  Tracks the execution of each step within a workflow run,
  including timing, input/output, and linked agent calls.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          workflow_run_id: Ecto.UUID.t() | nil,
          step_id: String.t() | nil,
          step_name: String.t() | nil,
          step_type: String.t() | nil,
          step_config: map() | nil,
          status: String.t(),
          input: map(),
          output: map(),
          agent_call_id: Ecto.UUID.t() | nil,
          approval_id: Ecto.UUID.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          duration_ms: integer() | nil,
          tokens_in: integer() | nil,
          tokens_out: integer() | nil,
          cost_cents: integer() | nil,
          error_type: String.t() | nil,
          error_message: String.t() | nil,
          attempt_number: integer(),
          max_attempts: integer(),
          sequence: integer() | nil,
          depends_on: [String.t()],
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @step_types ~w(agent_call rag_query shell approval python transform condition parallel)

  schema "workflow_steps" do
    field :step_id, :string
    field :step_name, :string
    field :step_type, :string
    field :step_config, :map
    field :status, :string, default: "pending"
    field :input, :map, default: %{}
    field :output, :map, default: %{}
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :duration_ms, :integer
    field :tokens_in, :integer
    field :tokens_out, :integer
    field :cost_cents, :integer
    field :error_type, :string
    field :error_message, :string
    field :attempt_number, :integer, default: 1
    field :max_attempts, :integer, default: 1
    field :sequence, :integer
    field :depends_on, {:array, :string}, default: []
    field :metadata, :map, default: %{}

    belongs_to :workflow_run, Command.Workflows.WorkflowRun
    belongs_to :agent_call, Command.Agents.AgentCall
    belongs_to :approval, Command.Approvals.ApprovalItem

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new workflow step.
  """
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(step, attrs) do
    step
    |> cast(attrs, [
      :workflow_run_id,
      :step_id,
      :step_name,
      :step_type,
      :step_config,
      :input,
      :sequence,
      :depends_on,
      :max_attempts,
      :metadata
    ])
    |> validate_required([
      :workflow_run_id,
      :step_id,
      :step_name,
      :step_type,
      :step_config,
      :sequence
    ])
    |> validate_inclusion(:step_type, @step_types)
    |> validate_number(:sequence, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:workflow_run_id)
  end

  @doc """
  Changeset for starting step execution.
  """
  @spec start_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def start_changeset(step, attrs \\ %{}) do
    step
    |> cast(attrs, [:input])
    |> put_change(:status, "running")
    |> put_change(:started_at, DateTime.utc_now())
  end

  @doc """
  Changeset for waiting on approval.
  """
  @spec waiting_approval_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def waiting_approval_changeset(step, attrs) do
    step
    |> cast(attrs, [:approval_id])
    |> put_change(:status, "waiting_approval")
  end

  @doc """
  Changeset for completing step execution successfully.
  """
  @spec complete_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def complete_changeset(step, attrs) do
    now = DateTime.utc_now()
    started_at = step.started_at || now
    duration_ms = DateTime.diff(now, started_at, :millisecond)

    step
    |> cast(attrs, [:output, :agent_call_id, :tokens_in, :tokens_out, :cost_cents])
    |> put_change(:status, "completed")
    |> put_change(:completed_at, now)
    |> put_change(:duration_ms, duration_ms)
  end

  @doc """
  Changeset for recording a failed step.
  """
  @spec failure_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def failure_changeset(step, attrs) do
    now = DateTime.utc_now()
    started_at = step.started_at || now
    duration_ms = DateTime.diff(now, started_at, :millisecond)

    step
    |> cast(attrs, [:error_type, :error_message])
    |> put_change(:status, "failed")
    |> put_change(:completed_at, now)
    |> put_change(:duration_ms, duration_ms)
  end

  @doc """
  Changeset for skipping a step.
  """
  @spec skip_changeset(t() | Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def skip_changeset(step) do
    step
    |> change(%{
      status: "skipped",
      completed_at: DateTime.utc_now()
    })
  end

  @doc """
  Changeset for retrying a step.
  """
  @spec retry_changeset(t() | Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def retry_changeset(step) do
    step
    |> change(%{
      status: "pending",
      attempt_number: (step.attempt_number || 1) + 1,
      started_at: nil,
      completed_at: nil,
      duration_ms: nil,
      error_type: nil,
      error_message: nil
    })
  end
end
