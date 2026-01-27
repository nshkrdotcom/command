defmodule Command.PlanRuns.PlanRun do
  @moduledoc """
  Schema for persisted plan run records.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(queued running succeeded failed cancelled paused skipped)

  schema "plan_runs" do
    field :plan_id, :binary_id
    field :plan_version, :string
    field :plan_hash, :string
    field :plan_ref, :string
    field :plan_data, :map, default: %{}
    field :status, :string, default: "queued"
    field :runtime, :string
    field :runtime_ref, :string
    field :work_id, :binary_id
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :user, Command.Accounts.User
    belongs_to :session, Command.Sessions.Session

    belongs_to :run_index_run, Command.RunIndex.Run,
      foreign_key: :run_index_run_id,
      type: :binary_id

    belongs_to :trace, LineageIR.Trace, foreign_key: :trace_id, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for plan runs.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(plan_run, attrs) do
    plan_run
    |> cast(attrs, [
      :user_id,
      :session_id,
      :plan_id,
      :plan_version,
      :plan_hash,
      :plan_ref,
      :plan_data,
      :status,
      :runtime,
      :runtime_ref,
      :run_index_run_id,
      :trace_id,
      :work_id,
      :started_at,
      :finished_at,
      :metadata
    ])
    |> validate_required([:user_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:session_id)
  end
end
