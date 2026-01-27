defmodule LineageIR.Span do
  @moduledoc """
  Lineage span schema.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @schema_prefix "lineage"
  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "spans" do
    field :trace_id, :binary_id
    field :parent_span_id, :binary_id
    field :run_id, :binary_id
    field :step_id, :binary_id
    field :work_id, :binary_id
    field :name, :string
    field :kind, :string
    field :status, :string
    field :attributes, :map
    field :metrics, :map
    field :error_type, :string
    field :error_message, :string
    field :error_details, :map
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for spans.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(span, attrs) do
    span
    |> cast(attrs, [
      :id,
      :trace_id,
      :parent_span_id,
      :run_id,
      :step_id,
      :work_id,
      :name,
      :kind,
      :status,
      :attributes,
      :metrics,
      :error_type,
      :error_message,
      :error_details,
      :started_at,
      :finished_at
    ])
    |> validate_required([:id, :trace_id, :name])
  end
end
