defmodule Command.Accounts do
  @moduledoc """
  The Accounts context.

  Manages users and their API credentials.
  """

  import Ecto.Query

  alias Command.Accounts.{ApiCredential, User}
  alias Command.Repo

  # Users

  @doc """
  Creates a new user.

  ## Examples

      iex> create_user(%{email: "user@example.com", name: "Test User"})
      {:ok, %User{}}

      iex> create_user(%{email: "invalid"})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def create_user(attrs) do
    %User{}
    |> User.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns a changeset for tracking user changes.

  ## Examples

      iex> change_user(user)
      %Ecto.Changeset{data: %User{}}

      iex> change_user(user, %{name: "New Name"})
      %Ecto.Changeset{data: %User{}}
  """
  @spec change_user(User.t(), map()) :: Ecto.Changeset.t()
  def change_user(%User{} = user, attrs \\ %{}) do
    User.create_changeset(user, attrs)
  end

  @doc """
  Gets a user by ID.
  """
  @spec get_user(Ecto.UUID.t()) :: User.t() | nil
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Gets a user by ID, raising if not found.
  """
  @spec get_user!(Ecto.UUID.t()) :: User.t()
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a user by email.
  """
  @spec get_user_by_email(String.t()) :: User.t() | nil
  def get_user_by_email(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Updates a user's profile.
  """
  @spec update_user_profile(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_profile(user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a user's preferences.
  """
  @spec update_user_preferences(User.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_preferences(user, preferences) do
    user
    |> User.preferences_changeset(%{preferences: preferences})
    |> Repo.update()
  end

  @doc """
  Updates a user's status.
  """
  @spec update_user_status(User.t(), String.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_status(user, status) do
    user
    |> User.status_changeset(%{status: status})
    |> Repo.update()
  end

  @doc """
  Lists all users.
  """
  @spec list_users(keyword()) :: [User.t()]
  def list_users(opts \\ []) do
    User
    |> apply_filters(opts)
    |> Repo.all()
  end

  # API Credentials

  @doc """
  Creates an API credential for a user.

  The API key is encrypted before storage.
  """
  @spec create_api_credential(User.t(), map()) ::
          {:ok, ApiCredential.t()} | {:error, Ecto.Changeset.t()}
  def create_api_credential(user, attrs) do
    attrs = Map.put(attrs, :user_id, user.id)

    %ApiCredential{}
    |> ApiCredential.create_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, credential} -> {:ok, %{credential | api_key: nil}}
      error -> error
    end
  end

  @doc """
  Returns a changeset for tracking API credential changes.

  ## Examples

      iex> change_api_credential(credential)
      %Ecto.Changeset{data: %ApiCredential{}}

      iex> change_api_credential(credential, %{name: "Primary Key"})
      %Ecto.Changeset{data: %ApiCredential{}}
  """
  @spec change_api_credential(ApiCredential.t(), map()) :: Ecto.Changeset.t()
  def change_api_credential(%ApiCredential{} = credential, attrs \\ %{}) do
    ApiCredential.create_changeset(credential, attrs)
  end

  @doc """
  Gets an API credential by ID.
  """
  @spec get_api_credential(Ecto.UUID.t()) :: ApiCredential.t() | nil
  def get_api_credential(id), do: Repo.get(ApiCredential, id)

  @doc """
  Gets an API credential for a user by provider.
  """
  @spec get_api_credential_by_provider(User.t(), String.t()) :: ApiCredential.t() | nil
  def get_api_credential_by_provider(user, provider) do
    ApiCredential
    |> where([c], c.user_id == ^user.id and c.provider == ^provider and c.status == "active")
    |> order_by([c], desc: c.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Lists API credentials for a user.
  """
  @spec list_api_credentials(User.t()) :: [ApiCredential.t()]
  def list_api_credentials(user) do
    ApiCredential
    |> where([c], c.user_id == ^user.id)
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  @doc """
  Revokes an API credential.
  """
  @spec revoke_api_credential(ApiCredential.t()) ::
          {:ok, ApiCredential.t()} | {:error, Ecto.Changeset.t()}
  def revoke_api_credential(credential) do
    credential
    |> ApiCredential.status_changeset(%{status: "revoked"})
    |> Repo.update()
  end

  @doc """
  Records API credential usage.
  """
  @spec record_credential_usage(ApiCredential.t()) ::
          {:ok, ApiCredential.t()} | {:error, Ecto.Changeset.t()}
  def record_credential_usage(credential) do
    credential
    |> ApiCredential.usage_changeset()
    |> Repo.update()
  end

  # Private helpers

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:status, status}, query ->
        where(query, [u], u.status == ^status)

      {:limit, limit}, query ->
        limit(query, ^limit)

      _, query ->
        query
    end)
  end
end
