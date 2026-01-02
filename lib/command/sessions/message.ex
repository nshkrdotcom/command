defmodule Command.Sessions.Message do
  @moduledoc """
  Schema for conversation messages within sessions.

  Messages represent the conversation history between users, agents,
  and tool results. They maintain ordering and can include attachments.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          session_id: Ecto.UUID.t() | nil,
          role: String.t() | nil,
          content: String.t() | nil,
          content_blocks: [map()],
          sequence: integer() | nil,
          agent_call_id: Ecto.UUID.t() | nil,
          tool_use_id: Ecto.UUID.t() | nil,
          visible_in_branches: [Ecto.UUID.t()],
          token_count: integer() | nil,
          attachments: [map()],
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(user assistant system tool_result)

  schema "messages" do
    field :role, :string
    field :content, :string
    field :content_blocks, {:array, :map}, default: []
    field :sequence, :integer
    field :visible_in_branches, {:array, :binary_id}, default: []
    field :token_count, :integer
    field :attachments, {:array, :map}, default: []
    field :metadata, :map, default: %{}

    belongs_to :session, Command.Sessions.Session
    belongs_to :agent_call, Command.Agents.AgentCall
    belongs_to :tool_use, Command.Agents.ToolUse

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new message.
  """
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(message, attrs) do
    message
    |> cast(attrs, [
      :session_id,
      :role,
      :content,
      :content_blocks,
      :sequence,
      :agent_call_id,
      :tool_use_id,
      :visible_in_branches,
      :token_count,
      :attachments,
      :metadata
    ])
    |> validate_required([:session_id, :role, :sequence])
    |> validate_inclusion(:role, @roles)
    |> validate_content_present()
    |> foreign_key_constraint(:session_id)
    |> foreign_key_constraint(:agent_call_id)
    |> foreign_key_constraint(:tool_use_id)
  end

  @doc """
  Changeset for updating message visibility in branches.
  """
  @spec branch_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def branch_changeset(message, attrs) do
    message
    |> cast(attrs, [:visible_in_branches])
  end

  @doc """
  Changeset for updating message metadata.
  """
  @spec metadata_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def metadata_changeset(message, attrs) do
    message
    |> cast(attrs, [:metadata, :token_count])
  end

  defp validate_content_present(changeset) do
    content = get_field(changeset, :content)
    content_blocks = get_field(changeset, :content_blocks)

    if is_nil(content) && Enum.empty?(content_blocks || []) do
      add_error(changeset, :content, "either content or content_blocks must be present")
    else
      changeset
    end
  end
end
