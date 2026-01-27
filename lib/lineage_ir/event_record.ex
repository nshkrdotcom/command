defmodule LineageIR.EventRecord do
  @moduledoc """
  Persisted event log for lineage sink.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @schema_prefix "lineage"
  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "events" do
    field :trace_id, :binary_id
    field :span_id, :binary_id
    field :event_type, :string
    field :occurred_at, :utc_datetime_usec
    field :source, :string
    field :source_ref, :string
    field :payload, :map

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for event records.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :id,
      :trace_id,
      :span_id,
      :event_type,
      :occurred_at,
      :source,
      :source_ref,
      :payload
    ])
    |> validate_required([:id, :event_type, :occurred_at])
  end
end
