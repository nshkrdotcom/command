defmodule Command.Pipelines.Template do
  @moduledoc """
  Schema for FlowStone pipeline templates.

  A template stores the pipeline definition and configuration used to
  execute FlowStone assets within Command.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type status :: :active | :inactive | :archived

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          status: status(),
          config: map(),
          template_id: Ecto.UUID.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "command_pipelines" do
    field :name, :string
    field :description, :string
    field :status, Ecto.Enum, values: [:active, :inactive, :archived], default: :active
    field :config, :map, default: %{}

    belongs_to :template, Command.Workflows.Workflow
    has_many :executions, Command.Pipelines.Execution, foreign_key: :pipeline_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating or updating pipeline templates.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(template, attrs) do
    template
    |> cast(attrs, [:name, :description, :status, :config, :template_id])
    |> validate_required([:name, :template_id])
    |> validate_length(:name, min: 1, max: 200)
    |> foreign_key_constraint(:template_id)
  end
end
