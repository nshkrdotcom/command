defmodule Command.Orchestration.AgentSession do
  @moduledoc """
  Schema for tracking Synapse agent sessions within Command.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type status :: :pending | :running | :completed | :failed | :cancelled

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          status: status(),
          signal_type: String.t() | nil,
          signal_id: String.t() | nil,
          input: map(),
          output: map(),
          error: map() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          duration_ms: integer() | nil,
          metadata: map(),
          agent_config_id: Ecto.UUID.t() | nil,
          session_id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "command_agent_sessions" do
    field :status, Ecto.Enum,
      values: [:pending, :running, :completed, :failed, :cancelled],
      default: :pending

    field :signal_type, :string
    field :signal_id, :string
    field :input, :map, default: %{}
    field :output, :map, default: %{}
    field :error, :map
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :duration_ms, :integer
    field :metadata, :map, default: %{}

    belongs_to :agent_config, Command.Orchestration.AgentConfig
    belongs_to :session, Command.Sessions.Session
    belongs_to :user, Command.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating or updating agent sessions.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :status,
      :signal_type,
      :signal_id,
      :input,
      :output,
      :error,
      :started_at,
      :completed_at,
      :duration_ms,
      :metadata,
      :agent_config_id,
      :session_id,
      :user_id
    ])
    |> validate_required([:agent_config_id, :session_id])
    |> foreign_key_constraint(:agent_config_id)
    |> foreign_key_constraint(:session_id)
    |> foreign_key_constraint(:user_id)
  end
end
