defmodule Command.Pipelines.Execution do
  @moduledoc """
  Schema for pipeline executions (runs).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type status :: :pending | :running | :completed | :failed | :cancelled

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          partition: String.t() | nil,
          status: status(),
          flowstone_run_id: String.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          result: map() | nil,
          error: map() | nil,
          pipeline_id: Ecto.UUID.t() | nil,
          session_id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "command_pipeline_runs" do
    field :partition, :string

    field :status, Ecto.Enum,
      values: [:pending, :running, :completed, :failed, :cancelled],
      default: :pending

    field :flowstone_run_id, :string
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :result, :map
    field :error, :map

    belongs_to :pipeline, Command.Pipelines.Template
    belongs_to :session, Command.Sessions.Session
    belongs_to :user, Command.Accounts.User
    has_many :ai_operations, Command.Pipelines.AIOperation, foreign_key: :pipeline_run_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating or updating pipeline executions.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(execution, attrs) do
    execution
    |> cast(attrs, [
      :partition,
      :status,
      :flowstone_run_id,
      :started_at,
      :completed_at,
      :result,
      :error,
      :pipeline_id,
      :session_id,
      :user_id
    ])
    |> validate_required([:pipeline_id, :partition])
    |> foreign_key_constraint(:pipeline_id)
    |> foreign_key_constraint(:session_id)
    |> foreign_key_constraint(:user_id)
  end
end
