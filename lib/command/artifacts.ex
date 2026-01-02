defmodule Command.Artifacts do
  @moduledoc """
  The Artifacts context.

  Manages files, outputs, and versioned assets.
  """

  import Ecto.Query

  alias Command.Accounts.User
  alias Command.Artifacts.Artifact
  alias Command.Repo
  alias Command.Sessions.Session

  @doc """
  Creates an artifact.
  """
  @spec create_artifact(User.t(), map()) :: {:ok, Artifact.t()} | {:error, Ecto.Changeset.t()}
  def create_artifact(user, attrs) do
    attrs = Map.put(attrs, :user_id, user.id)

    %Artifact{}
    |> Artifact.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns a changeset for tracking artifact changes.

  ## Examples

      iex> change_artifact(artifact)
      %Ecto.Changeset{data: %Artifact{}}

      iex> change_artifact(artifact, %{name: "Updated"})
      %Ecto.Changeset{data: %Artifact{}}
  """
  @spec change_artifact(Artifact.t(), map()) :: Ecto.Changeset.t()
  def change_artifact(%Artifact{} = artifact, attrs \\ %{}) do
    Artifact.create_changeset(artifact, attrs)
  end

  @doc """
  Gets an artifact by ID.
  """
  @spec get_artifact(Ecto.UUID.t()) :: Artifact.t() | nil
  def get_artifact(id), do: Repo.get(Artifact, id)

  @doc """
  Creates a new version of an artifact.
  """
  @spec create_artifact_version(Artifact.t(), map()) ::
          {:ok, Artifact.t()} | {:error, Ecto.Changeset.t()}
  def create_artifact_version(previous, attrs) do
    Repo.transaction(fn ->
      # Mark previous as not latest
      {:ok, _} =
        previous
        |> Artifact.supersede_changeset()
        |> Repo.update()

      # Create new version
      {:ok, new} =
        %Artifact{}
        |> Artifact.new_version_changeset(previous, attrs)
        |> Repo.insert()

      new
    end)
  end

  @doc """
  Creates a diff artifact.
  """
  @spec create_diff(User.t(), Artifact.t(), map()) ::
          {:ok, Artifact.t()} | {:error, Ecto.Changeset.t()}
  def create_diff(user, base_artifact, attrs) do
    attrs =
      attrs
      |> Map.put(:user_id, user.id)
      |> Map.put(:diff_base_artifact_id, base_artifact.id)

    %Artifact{}
    |> Artifact.diff_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists artifacts for a user.
  """
  @spec list_artifacts(User.t(), keyword()) :: [Artifact.t()]
  def list_artifacts(user, opts \\ []) do
    Artifact
    |> where([a], a.user_id == ^user.id)
    |> apply_artifact_filters(opts)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists artifacts for a session.
  """
  @spec list_session_artifacts(Session.t(), keyword()) :: [Artifact.t()]
  def list_session_artifacts(session, opts \\ []) do
    Artifact
    |> where([a], a.session_id == ^session.id)
    |> apply_artifact_filters(opts)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets version history for an artifact.
  """
  @spec get_version_history(Artifact.t()) :: [Artifact.t()]
  def get_version_history(artifact) do
    # Find the root artifact
    root = find_root_artifact(artifact)

    # Get all versions from root
    get_all_versions(root, [root])
    |> Enum.sort_by(& &1.version)
  end

  @doc """
  Deletes an artifact.
  """
  @spec delete_artifact(Artifact.t()) :: {:ok, Artifact.t()} | {:error, Ecto.Changeset.t()}
  def delete_artifact(artifact) do
    Repo.delete(artifact)
  end

  @doc """
  Deletes expired artifacts.
  """
  @spec delete_expired_artifacts() :: {integer(), nil}
  def delete_expired_artifacts do
    now = DateTime.utc_now()

    Artifact
    |> where([a], a.expires_at < ^now)
    |> Repo.delete_all()
  end

  # Private helpers

  defp find_root_artifact(artifact) do
    case artifact.previous_version_id do
      nil ->
        artifact

      previous_id ->
        Repo.get!(Artifact, previous_id)
        |> find_root_artifact()
    end
  end

  defp get_all_versions(artifact, acc) do
    newer =
      Artifact
      |> where([a], a.previous_version_id == ^artifact.id)
      |> Repo.all()

    case newer do
      [] -> acc
      versions -> Enum.reduce(versions, acc ++ versions, &get_all_versions(&1, &2))
    end
  end

  defp apply_artifact_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:artifact_type, type}, query ->
        where(query, [a], a.artifact_type == ^type)

      {:is_latest, true}, query ->
        where(query, [a], a.is_latest == true)

      {:tags, tags}, query when is_list(tags) ->
        where(query, [a], fragment("? && ?", a.tags, ^tags))

      {:limit, limit}, query ->
        limit(query, ^limit)

      _, query ->
        query
    end)
  end
end
