defmodule LineageIR.ProvenanceEdge do
  @moduledoc """
  Lineage provenance edge schema.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @schema_prefix "lineage"
  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "edges" do
    field :trace_id, :binary_id
    field :source_type, :string
    field :source_id, :binary_id
    field :target_type, :string
    field :target_id, :binary_id
    field :relationship, :string
    field :metadata, :map

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for provenance edges.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(edge, attrs) do
    edge
    |> cast(attrs, [
      :id,
      :trace_id,
      :source_type,
      :source_id,
      :target_type,
      :target_id,
      :relationship,
      :metadata
    ])
    |> validate_required([:id, :source_type, :source_id, :target_type, :target_id, :relationship])
  end
end
