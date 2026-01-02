defmodule Command.Presence.ActivityLog do
  @moduledoc """
  Schema for audit trail of user actions.

  Records all significant actions for compliance,
  debugging, and analytics purposes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          action: String.t() | nil,
          resource_type: String.t() | nil,
          resource_id: Ecto.UUID.t() | nil,
          details: map(),
          session_id: Ecto.UUID.t() | nil,
          client_id: String.t() | nil,
          ip_address: String.t() | nil,
          occurred_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @actions ~w(
    session.create session.update session.archive session.fork
    message.create message.delete
    agent.call.start agent.call.complete agent.call.fail
    tool.execute tool.approve tool.deny
    workflow.create workflow.run.start workflow.run.complete workflow.run.fail
    index.create index.update index.delete
    approval.create approval.approve approval.deny approval.expire
    artifact.create artifact.update artifact.delete
    user.login user.logout user.update
  )

  schema "activity_logs" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, :binary_id
    field :details, :map, default: %{}
    field :session_id, :binary_id
    field :client_id, :string
    field :ip_address, :string
    field :occurred_at, :utc_datetime_usec

    belongs_to :user, Command.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new activity log entry.
  """
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(log, attrs) do
    log
    |> cast(attrs, [
      :user_id,
      :action,
      :resource_type,
      :resource_id,
      :details,
      :session_id,
      :client_id,
      :ip_address,
      :occurred_at
    ])
    |> validate_required([:action, :resource_type, :resource_id])
    |> validate_inclusion(:action, @actions)
    |> put_default_occurred_at()
    |> foreign_key_constraint(:user_id)
  end

  defp put_default_occurred_at(changeset) do
    case get_field(changeset, :occurred_at) do
      nil -> put_change(changeset, :occurred_at, DateTime.utc_now())
      _ -> changeset
    end
  end

  @doc """
  Returns the list of valid actions.
  """
  @spec valid_actions() :: [String.t()]
  def valid_actions, do: @actions
end
