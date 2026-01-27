defmodule Command.RunIndex.Step do
  @moduledoc """
  RunIndex step record for per-step execution tracking.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @schema_prefix "run_index"
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @required_fields ~w(run_id step_key action_name status)a

  schema "steps" do
    field :step_id, :binary_id
    field :step_key, :string
    field :action_name, :string
    field :action_module, :string
    field :tool_name, :string
    field :status, :string
    field :status_reason, :string
    field :work_id, :binary_id
    field :trace_id, :binary_id
    field :span_id, :binary_id
    field :attempt, :integer, default: 1
    field :max_attempts, :integer
    field :queue, :string
    field :inputs, :map
    field :output_artifact_refs, :map
    field :cost_usd, :decimal
    field :usage, :map
    field :error_type, :string
    field :error_message, :string
    field :error_details, :map
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    belongs_to :run, Command.RunIndex.Run, foreign_key: :run_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for RunIndex steps.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(step, attrs) do
    step
    |> cast(attrs, [
      :run_id,
      :step_id,
      :step_key,
      :action_name,
      :action_module,
      :tool_name,
      :status,
      :status_reason,
      :work_id,
      :trace_id,
      :span_id,
      :attempt,
      :max_attempts,
      :queue,
      :inputs,
      :output_artifact_refs,
      :cost_usd,
      :usage,
      :error_type,
      :error_message,
      :error_details,
      :started_at,
      :finished_at
    ])
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:run_id)
  end
end
