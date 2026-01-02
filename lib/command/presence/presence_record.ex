defmodule Command.Presence.PresenceRecord do
  @moduledoc """
  Schema for tracking user presence in resources.

  Complements Phoenix.Presence with persistence for
  tracking who is viewing or editing what.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          resource_type: String.t() | nil,
          resource_id: Ecto.UUID.t() | nil,
          status: String.t(),
          client_id: String.t() | nil,
          device_type: String.t() | nil,
          user_agent: String.t() | nil,
          cursor_state: map(),
          joined_at: DateTime.t() | nil,
          last_seen_at: DateTime.t() | nil,
          left_at: DateTime.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @resource_types ~w(session workflow_run approval_item)
  @statuses ~w(viewing editing idle away)
  @device_types ~w(desktop mobile tablet)

  schema "presence_records" do
    field :resource_type, :string
    field :resource_id, :binary_id
    field :status, :string, default: "viewing"
    field :client_id, :string
    field :device_type, :string
    field :user_agent, :string
    field :cursor_state, :map, default: %{}
    field :joined_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec
    field :left_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :user, Command.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new presence record.
  """
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(presence, attrs) do
    now = DateTime.utc_now()

    presence
    |> cast(attrs, [
      :user_id,
      :resource_type,
      :resource_id,
      :client_id,
      :device_type,
      :user_agent,
      :metadata
    ])
    |> validate_required([:user_id, :resource_type, :resource_id, :client_id])
    |> validate_inclusion(:resource_type, @resource_types)
    |> validate_inclusion(:device_type, @device_types ++ [nil])
    |> put_change(:joined_at, now)
    |> put_change(:last_seen_at, now)
    |> unique_constraint(:client_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for updating presence status.
  """
  @spec status_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def status_changeset(presence, attrs) do
    presence
    |> cast(attrs, [:status, :cursor_state])
    |> validate_inclusion(:status, @statuses)
    |> put_change(:last_seen_at, DateTime.utc_now())
  end

  @doc """
  Changeset for heartbeat/ping.
  """
  @spec heartbeat_changeset(t() | Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def heartbeat_changeset(presence) do
    presence
    |> change(%{last_seen_at: DateTime.utc_now()})
  end

  @doc """
  Changeset for recording departure.
  """
  @spec leave_changeset(t() | Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def leave_changeset(presence) do
    presence
    |> change(%{left_at: DateTime.utc_now()})
  end
end
