defmodule Command.RunIndex.Run do
  @moduledoc """
  RunIndex run record for cross-runtime execution tracking.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @schema_prefix "run_index"
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @required_fields ~w(runtime runtime_ref status)a

  schema "runs" do
    field :root_run_id, :binary_id
    field :parent_run_id, :binary_id
    field :plan_id, :binary_id
    field :plan_version, :string
    field :plan_hash, :string
    field :plan_ref, :string
    field :runtime, :string
    field :runtime_ref, :string
    field :status, :string
    field :status_reason, :string
    field :work_id, :binary_id
    field :trace_id, :binary_id
    field :session_id, :binary_id
    field :actor_type, :string
    field :actor_id, :binary_id
    field :tenant_id, :binary_id
    field :inputs, :map
    field :output_artifact_refs, :map
    field :labels, :map
    field :cost_usd, :decimal
    field :usage, :map
    field :error_type, :string
    field :error_message, :string
    field :error_details, :map
    field :scheduled_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for RunIndex runs.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :root_run_id,
      :parent_run_id,
      :plan_id,
      :plan_version,
      :plan_hash,
      :plan_ref,
      :runtime,
      :runtime_ref,
      :status,
      :status_reason,
      :work_id,
      :trace_id,
      :session_id,
      :actor_type,
      :actor_id,
      :tenant_id,
      :inputs,
      :output_artifact_refs,
      :labels,
      :cost_usd,
      :usage,
      :error_type,
      :error_message,
      :error_details,
      :scheduled_at,
      :started_at,
      :finished_at
    ])
    |> validate_required(@required_fields)
  end
end
