defmodule Command.Accounts.User do
  @moduledoc """
  Schema for user accounts.

  Users are the primary actors in the system and own all resources
  including sessions, workflows, indexes, and credentials.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          email: String.t() | nil,
          name: String.t() | nil,
          avatar_url: String.t() | nil,
          auth_provider: String.t() | nil,
          auth_uid: String.t() | nil,
          password_hash: String.t() | nil,
          preferences: map(),
          api_keys: map(),
          status: String.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(active inactive suspended)

  schema "users" do
    field :email, :string
    field :name, :string
    field :avatar_url, :string
    field :auth_provider, :string
    field :auth_uid, :string
    field :password_hash, :string
    field :preferences, :map, default: %{}
    field :api_keys, :map, default: %{}
    field :status, :string, default: "active"

    # Virtual fields
    field :password, :string, virtual: true

    # Associations
    has_many :sessions, Command.Sessions.Session
    has_many :workflows, Command.Workflows.Workflow
    has_many :indexes, Command.Indexes.Index
    has_many :api_credentials, Command.Accounts.ApiCredential
    has_many :approval_rules, Command.Approvals.ApprovalRule
    has_many :scheduled_jobs, Command.Scheduling.ScheduledJob
    has_many :cost_records, Command.Costs.CostRecord
    has_many :cost_daily_summaries, Command.Costs.CostDailySummary
    has_many :activity_logs, Command.Presence.ActivityLog
    has_many :presence_records, Command.Presence.PresenceRecord

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new user.
  """
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :avatar_url, :auth_provider, :auth_uid, :password])
    |> validate_required([:email])
    |> validate_email()
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:email)
    |> unique_constraint([:auth_provider, :auth_uid])
    |> maybe_hash_password()
  end

  @doc """
  Changeset for updating user preferences.
  """
  @spec preferences_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def preferences_changeset(user, attrs) do
    user
    |> cast(attrs, [:preferences])
    |> validate_required([:preferences])
  end

  @doc """
  Changeset for updating user profile.
  """
  @spec profile_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :avatar_url])
  end

  @doc """
  Changeset for updating user status.
  """
  @spec status_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def status_changeset(user, attrs) do
    user
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end

  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have @ sign and no spaces")
    |> validate_length(:email, max: 254)
  end

  defp maybe_hash_password(changeset) do
    case get_change(changeset, :password) do
      nil ->
        changeset

      password ->
        # Using a simple hash for now; in production use Bcrypt or Argon2
        hash = :crypto.hash(:sha256, password) |> Base.encode16(case: :lower)
        put_change(changeset, :password_hash, hash)
    end
  end
end
