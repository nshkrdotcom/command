defmodule Command.Workflows.WorkflowRun do
  @moduledoc """
  Schema for workflow execution instances.

  Tracks individual runs of workflows including status, timing,
  input/output, and cost aggregation.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          workflow_id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          session_id: Ecto.UUID.t() | nil,
          workflow_snapshot: map() | nil,
          status: String.t(),
          input: map(),
          output: map(),
          current_step_id: String.t() | nil,
          completed_step_ids: [String.t()],
          failed_step_id: String.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          duration_ms: integer() | nil,
          total_tokens_in: integer(),
          total_tokens_out: integer(),
          total_cost_cents: integer(),
          trigger_type: String.t() | nil,
          trigger_metadata: map(),
          error_type: String.t() | nil,
          error_message: String.t() | nil,
          error_step_id: String.t() | nil,
          git_context: map(),
          retry_of_run_id: Ecto.UUID.t() | nil,
          retry_count: integer(),
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @trigger_types ~w(manual schedule webhook api)

  schema "workflow_runs" do
    field :workflow_snapshot, :map
    field :status, :string, default: "pending"
    field :input, :map, default: %{}
    field :output, :map, default: %{}
    field :current_step_id, :string
    field :completed_step_ids, {:array, :string}, default: []
    field :failed_step_id, :string
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :duration_ms, :integer
    field :total_tokens_in, :integer, default: 0
    field :total_tokens_out, :integer, default: 0
    field :total_cost_cents, :integer, default: 0
    field :trigger_type, :string
    field :trigger_metadata, :map, default: %{}
    field :error_type, :string
    field :error_message, :string
    field :error_step_id, :string
    field :git_context, :map, default: %{}
    field :retry_count, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :workflow, Command.Workflows.Workflow
    belongs_to :user, Command.Accounts.User
    belongs_to :session, Command.Sessions.Session
    belongs_to :retry_of_run, Command.Workflows.WorkflowRun

    has_many :steps, Command.Workflows.WorkflowStep
    has_many :agent_calls, Command.Agents.AgentCall
    has_many :retries, Command.Workflows.WorkflowRun, foreign_key: :retry_of_run_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new workflow run.
  """
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(run, attrs) do
    run
    |> cast(attrs, [
      :workflow_id,
      :user_id,
      :session_id,
      :workflow_snapshot,
      :input,
      :trigger_type,
      :trigger_metadata,
      :git_context,
      :retry_of_run_id,
      :metadata
    ])
    |> validate_required([:workflow_id, :user_id, :workflow_snapshot])
    |> validate_inclusion(:trigger_type, @trigger_types ++ [nil])
    |> foreign_key_constraint(:workflow_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:session_id)
  end

  @doc """
  Changeset for starting a workflow run.
  """
  @spec start_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def start_changeset(run, attrs \\ %{}) do
    run
    |> cast(attrs, [:current_step_id])
    |> put_change(:status, "running")
    |> put_change(:started_at, DateTime.utc_now())
  end

  @doc """
  Changeset for updating run progress.
  """
  @spec progress_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def progress_changeset(run, attrs) do
    run
    |> cast(attrs, [:current_step_id, :completed_step_ids, :output])
  end

  @doc """
  Changeset for pausing a workflow run.
  """
  @spec pause_changeset(t() | Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def pause_changeset(run) do
    run
    |> change(%{status: "paused"})
  end

  @doc """
  Changeset for waiting on approval.
  """
  @spec waiting_approval_changeset(t() | Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def waiting_approval_changeset(run) do
    run
    |> change(%{status: "waiting_approval"})
  end

  @doc """
  Changeset for completing a workflow run successfully.
  """
  @spec complete_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def complete_changeset(run, attrs) do
    now = DateTime.utc_now()
    started_at = run.started_at || now
    duration_ms = DateTime.diff(now, started_at, :millisecond)

    run
    |> cast(attrs, [:output, :total_tokens_in, :total_tokens_out, :total_cost_cents])
    |> put_change(:status, "completed")
    |> put_change(:completed_at, now)
    |> put_change(:duration_ms, duration_ms)
  end

  @doc """
  Changeset for recording a failed workflow run.
  """
  @spec failure_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def failure_changeset(run, attrs) do
    now = DateTime.utc_now()
    started_at = run.started_at || now
    duration_ms = DateTime.diff(now, started_at, :millisecond)

    run
    |> cast(attrs, [:error_type, :error_message, :error_step_id, :failed_step_id])
    |> put_change(:status, "failed")
    |> put_change(:completed_at, now)
    |> put_change(:duration_ms, duration_ms)
  end

  @doc """
  Changeset for cancelling a workflow run.
  """
  @spec cancel_changeset(t() | Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def cancel_changeset(run) do
    now = DateTime.utc_now()
    started_at = run.started_at || now
    duration_ms = DateTime.diff(now, started_at, :millisecond)

    run
    |> change(%{
      status: "cancelled",
      completed_at: now,
      duration_ms: duration_ms
    })
  end
end
