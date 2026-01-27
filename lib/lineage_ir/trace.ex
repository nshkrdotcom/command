defmodule LineageIR.Trace do
  @moduledoc """
  Lineage trace schema.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @schema_prefix "lineage"
  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "traces" do
    field :root_trace_id, :binary_id
    field :parent_trace_id, :binary_id
    field :run_id, :binary_id
    field :work_id, :binary_id
    field :origin, :string
    field :origin_ref, :string
    field :status, :string
    field :attributes, :map
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for traces.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(trace, attrs) do
    trace
    |> cast(attrs, [
      :id,
      :root_trace_id,
      :parent_trace_id,
      :run_id,
      :work_id,
      :origin,
      :origin_ref,
      :status,
      :attributes,
      :started_at,
      :finished_at
    ])
    |> validate_required([:id])
  end
end
