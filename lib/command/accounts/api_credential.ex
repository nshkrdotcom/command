defmodule Command.Accounts.ApiCredential do
  @moduledoc """
  Schema for API credentials.

  Stores encrypted API keys for various providers (Anthropic, OpenAI, etc.)
  with usage tracking and validation status.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          provider: String.t() | nil,
          encrypted_key: binary() | nil,
          key_hint: String.t() | nil,
          status: String.t(),
          last_validated_at: DateTime.t() | nil,
          validation_error: String.t() | nil,
          last_used_at: DateTime.t() | nil,
          use_count: integer(),
          scopes: [String.t()],
          expires_at: DateTime.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @providers ~w(anthropic openai google cohere github gitlab)
  @statuses ~w(active revoked expired)

  schema "api_credentials" do
    field :name, :string
    field :provider, :string
    field :encrypted_key, Command.EncryptedBinary
    field :key_hint, :string
    field :status, :string, default: "active"
    field :last_validated_at, :utc_datetime_usec
    field :validation_error, :string
    field :last_used_at, :utc_datetime_usec
    field :use_count, :integer, default: 0
    field :scopes, {:array, :string}, default: []
    field :expires_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    # Virtual field for the raw key
    field :api_key, :string, virtual: true

    belongs_to :user, Command.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new API credential.
  """
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(credential, attrs) do
    credential
    |> cast(attrs, [:name, :provider, :api_key, :user_id, :scopes, :expires_at, :metadata])
    |> validate_required([:name, :provider, :api_key, :user_id])
    |> validate_inclusion(:provider, @providers)
    |> validate_length(:name, min: 1, max: 100)
    |> encrypt_api_key()
    |> set_key_hint()
    |> unique_constraint([:user_id, :provider, :name])
  end

  @doc """
  Changeset for updating credential status.
  """
  @spec status_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def status_changeset(credential, attrs) do
    credential
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end

  @doc """
  Changeset for recording credential usage.
  """
  @spec usage_changeset(t() | Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def usage_changeset(credential) do
    credential
    |> change(%{
      last_used_at: DateTime.utc_now(),
      use_count: (credential.use_count || 0) + 1
    })
  end

  @doc """
  Changeset for recording validation result.
  """
  @spec validation_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def validation_changeset(credential, attrs) do
    credential
    |> cast(attrs, [:last_validated_at, :validation_error])
    |> put_change(:last_validated_at, DateTime.utc_now())
  end

  defp encrypt_api_key(changeset) do
    case get_change(changeset, :api_key) do
      nil -> changeset
      key -> put_change(changeset, :encrypted_key, key)
    end
  end

  defp set_key_hint(changeset) do
    case get_change(changeset, :api_key) do
      nil ->
        changeset

      key when byte_size(key) >= 4 ->
        hint = String.slice(key, -4, 4)
        put_change(changeset, :key_hint, hint)

      _ ->
        changeset
    end
  end
end
