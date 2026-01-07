defmodule Command.Orchestration.AgentConfig do
  @moduledoc """
  Schema for persisted Synapse agent configurations.

  Stores the canonical agent definition so Command can
  rehydrate and manage Synapse agents at runtime.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type agent_type :: :specialist | :orchestrator | :custom
  @type status :: :active | :inactive | :archived

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          agent_id: String.t() | nil,
          type: agent_type() | nil,
          status: status(),
          config: map(),
          signals: map(),
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "command_agent_configs" do
    field :agent_id, :string
    field :type, Ecto.Enum, values: [:specialist, :orchestrator, :custom]
    field :status, Ecto.Enum, values: [:active, :inactive, :archived], default: :active
    field :config, :map, default: %{}
    field :signals, :map, default: %{}
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating or updating agent configs.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(config, attrs) do
    config
    |> cast(attrs, [:agent_id, :type, :status, :config, :signals, :metadata])
    |> validate_required([:agent_id, :type])
    |> validate_length(:agent_id, min: 1, max: 200)
    |> unique_constraint(:agent_id)
  end
end
