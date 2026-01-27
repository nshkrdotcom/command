defmodule Command.Lineage.ProvenanceEdge do
  @moduledoc """
  Schema for provenance edges in the lineage graph.

  Provenance edges connect artifacts, runs, steps, requirements, and other
  entities to form a complete lineage graph for traceability and audit.

  ## Relationship Types

  - `implements` - Code artifact implements a requirement
  - `created_by` - Artifact was created by a run
  - `step_of` - Step belongs to a run
  - `input_to` - Artifact was input to a step
  - `output_of` - Step produced an artifact
  - `triggered_by` - Run was triggered by a doc set
  - `released_in` - Artifact was included in a release
  - `derives_from` - Artifact was derived from another artifact
  - `prompt_in` - Prompt was used in a prompt step run
  - `response_from` - Response was produced by a prompt step run
  - `diff_for` - Diff is associated with a prompt step run
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "lineage"

  @relationships ~w(
    implements created_by step_of input_to output_of
    triggered_by released_in derives_from prompt_in
    response_from diff_for
  )

  schema "provenance_edges" do
    field :source_type, :string
    field :source_id, :string
    field :target_type, :string
    field :target_id, :string
    field :relationship, :string
    field :metadata, :map, default: %{}
    field :created_at, :utc_datetime_usec
  end

  @doc false
  def changeset(provenance_edge, attrs) do
    provenance_edge
    |> cast(attrs, [:source_type, :source_id, :target_type, :target_id, :relationship, :metadata])
    |> validate_required([:source_type, :source_id, :target_type, :target_id, :relationship])
    |> validate_inclusion(:relationship, @relationships)
    |> put_change(:created_at, DateTime.utc_now())
  end

  @doc """
  Returns the list of valid relationship types.
  """
  def relationships, do: @relationships
end
