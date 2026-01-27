defmodule LineageIR.Artifact do
  @moduledoc """
  Lineage artifact schema.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @schema_prefix "lineage"
  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "artifacts" do
    field :trace_id, :binary_id
    field :span_id, :binary_id
    field :run_id, :binary_id
    field :step_id, :binary_id
    field :type, :string
    field :uri, :string
    field :checksum, :string
    field :size_bytes, :integer
    field :mime_type, :string
    field :metadata, :map
    field :created_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for artifacts.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [
      :id,
      :trace_id,
      :span_id,
      :run_id,
      :step_id,
      :type,
      :uri,
      :checksum,
      :size_bytes,
      :mime_type,
      :metadata,
      :created_at
    ])
    |> validate_required([:id, :type])
  end
end
