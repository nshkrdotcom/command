defmodule Command.Artifacts.Artifact do
  @moduledoc """
  Schema for files, outputs, and versioned assets.

  Artifacts track generated content with versioning support,
  git linkage, and storage backend flexibility.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          session_id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          artifact_type: String.t() | nil,
          mime_type: String.t() | nil,
          storage_backend: String.t() | nil,
          storage_path: String.t() | nil,
          storage_key: String.t() | nil,
          inline_content: binary() | nil,
          size_bytes: integer() | nil,
          checksum: String.t() | nil,
          original_filename: String.t() | nil,
          language: String.t() | nil,
          line_count: integer() | nil,
          source_type: String.t() | nil,
          source_id: Ecto.UUID.t() | nil,
          version: integer(),
          previous_version_id: Ecto.UUID.t() | nil,
          is_latest: boolean(),
          git_commit: String.t() | nil,
          git_repo: String.t() | nil,
          git_path: String.t() | nil,
          diff_base_artifact_id: Ecto.UUID.t() | nil,
          diff_content: String.t() | nil,
          additions: integer() | nil,
          deletions: integer() | nil,
          visibility: String.t(),
          shared_with_user_ids: [Ecto.UUID.t()],
          expires_at: DateTime.t() | nil,
          retention_policy: String.t() | nil,
          tags: [String.t()],
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @artifact_types ~w(file code diff image document archive other)
  @storage_backends ~w(local s3 inline)
  @visibilities ~w(private shared public)
  @retention_policies ~w(permanent session temporary)
  @source_types ~w(agent_output tool_result upload workflow)

  schema "artifacts" do
    field :name, :string
    field :description, :string
    field :artifact_type, :string
    field :mime_type, :string
    field :storage_backend, :string
    field :storage_path, :string
    field :storage_key, :string
    field :inline_content, :binary
    field :size_bytes, :integer
    field :checksum, :string
    field :original_filename, :string
    field :language, :string
    field :line_count, :integer
    field :source_type, :string
    field :source_id, :binary_id
    field :version, :integer, default: 1
    field :is_latest, :boolean, default: true
    field :git_commit, :string
    field :git_repo, :string
    field :git_path, :string
    field :diff_content, :string
    field :additions, :integer
    field :deletions, :integer
    field :visibility, :string, default: "private"
    field :shared_with_user_ids, {:array, :binary_id}, default: []
    field :expires_at, :utc_datetime_usec
    field :retention_policy, :string
    field :tags, {:array, :string}, default: []
    field :metadata, :map, default: %{}

    belongs_to :user, Command.Accounts.User
    belongs_to :session, Command.Sessions.Session
    belongs_to :previous_version, Command.Artifacts.Artifact
    belongs_to :diff_base_artifact, Command.Artifacts.Artifact

    has_many :newer_versions, Command.Artifacts.Artifact, foreign_key: :previous_version_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new artifact.
  """
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [
      :user_id,
      :session_id,
      :name,
      :description,
      :artifact_type,
      :mime_type,
      :storage_backend,
      :storage_path,
      :storage_key,
      :inline_content,
      :size_bytes,
      :checksum,
      :original_filename,
      :language,
      :line_count,
      :source_type,
      :source_id,
      :git_commit,
      :git_repo,
      :git_path,
      :visibility,
      :shared_with_user_ids,
      :expires_at,
      :retention_policy,
      :tags,
      :metadata
    ])
    |> validate_required([:user_id, :name, :artifact_type, :storage_backend])
    |> validate_inclusion(:artifact_type, @artifact_types)
    |> validate_inclusion(:storage_backend, @storage_backends)
    |> validate_inclusion(:visibility, @visibilities)
    |> validate_inclusion(:retention_policy, @retention_policies ++ [nil])
    |> validate_inclusion(:source_type, @source_types ++ [nil])
    |> validate_storage()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:session_id)
  end

  @doc """
  Changeset for creating a new version of an artifact.
  """
  @spec new_version_changeset(t() | Ecto.Changeset.t(), t(), map()) :: Ecto.Changeset.t()
  def new_version_changeset(artifact, previous, attrs) do
    artifact
    |> create_changeset(attrs)
    |> put_change(:previous_version_id, previous.id)
    |> put_change(:version, (previous.version || 0) + 1)
    |> put_change(:is_latest, true)
  end

  @doc """
  Changeset for creating a diff artifact.
  """
  @spec diff_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def diff_changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [
      :user_id,
      :session_id,
      :name,
      :diff_base_artifact_id,
      :diff_content,
      :additions,
      :deletions,
      :metadata
    ])
    |> put_change(:artifact_type, "diff")
    |> put_change(:storage_backend, "inline")
    |> validate_required([:user_id, :name, :diff_base_artifact_id, :diff_content])
    |> foreign_key_constraint(:diff_base_artifact_id)
  end

  @doc """
  Changeset for marking an artifact as not latest.
  """
  @spec supersede_changeset(t() | Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def supersede_changeset(artifact) do
    artifact
    |> change(%{is_latest: false})
  end

  @doc """
  Changeset for updating artifact metadata.
  """
  @spec update_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def update_changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [
      :name,
      :description,
      :visibility,
      :shared_with_user_ids,
      :expires_at,
      :retention_policy,
      :tags,
      :metadata
    ])
    |> validate_inclusion(:visibility, @visibilities)
    |> validate_inclusion(:retention_policy, @retention_policies ++ [nil])
  end

  defp validate_storage(changeset) do
    backend = get_field(changeset, :storage_backend)
    path = get_field(changeset, :storage_path)
    key = get_field(changeset, :storage_key)
    inline = get_field(changeset, :inline_content)

    case backend do
      "local" when is_nil(path) ->
        add_error(changeset, :storage_path, "is required for local storage")

      "s3" when is_nil(key) ->
        add_error(changeset, :storage_key, "is required for S3 storage")

      "inline" when is_nil(inline) ->
        add_error(changeset, :inline_content, "is required for inline storage")

      _ ->
        changeset
    end
  end
end
