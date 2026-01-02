defmodule Command.Agents.ToolUse do
  @moduledoc """
  Schema for tool invocations within agent calls.

  Tracks tool usage including approval workflow, execution details,
  and file/shell operation results.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          agent_call_id: Ecto.UUID.t() | nil,
          session_id: Ecto.UUID.t() | nil,
          tool_name: String.t() | nil,
          tool_use_id: String.t() | nil,
          input: map() | nil,
          output: String.t() | nil,
          output_truncated: boolean(),
          status: String.t(),
          requires_approval: boolean(),
          approval_id: Ecto.UUID.t() | nil,
          approved_by_id: Ecto.UUID.t() | nil,
          approved_at: DateTime.t() | nil,
          denial_reason: String.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          duration_ms: integer() | nil,
          file_changes: [map()],
          exit_code: integer() | nil,
          stdout: String.t() | nil,
          stderr: String.t() | nil,
          error_type: String.t() | nil,
          error_message: String.t() | nil,
          sequence: integer() | nil,
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tool_uses" do
    field :tool_name, :string
    field :tool_use_id, :string
    field :input, :map
    field :output, :string
    field :output_truncated, :boolean, default: false
    field :status, :string, default: "pending"
    field :requires_approval, :boolean, default: false
    field :approved_at, :utc_datetime_usec
    field :denial_reason, :string
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :duration_ms, :integer
    field :file_changes, {:array, :map}, default: []
    field :exit_code, :integer
    field :stdout, :string
    field :stderr, :string
    field :error_type, :string
    field :error_message, :string
    field :sequence, :integer
    field :metadata, :map, default: %{}

    belongs_to :agent_call, Command.Agents.AgentCall
    belongs_to :session, Command.Sessions.Session
    belongs_to :approval, Command.Approvals.ApprovalItem
    belongs_to :approved_by, Command.Accounts.User

    has_one :message, Command.Sessions.Message

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new tool use.
  """
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(tool_use, attrs) do
    tool_use
    |> cast(attrs, [
      :agent_call_id,
      :session_id,
      :tool_name,
      :tool_use_id,
      :input,
      :sequence,
      :requires_approval,
      :metadata
    ])
    |> validate_required([:agent_call_id, :session_id, :tool_name, :input, :sequence])
    |> validate_length(:tool_name, min: 1, max: 100)
    |> foreign_key_constraint(:agent_call_id)
    |> foreign_key_constraint(:session_id)
  end

  @doc """
  Changeset for approving a tool use.
  """
  @spec approve_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def approve_changeset(tool_use, attrs) do
    tool_use
    |> cast(attrs, [:approved_by_id, :approval_id])
    |> put_change(:status, "approved")
    |> put_change(:approved_at, DateTime.utc_now())
    |> foreign_key_constraint(:approved_by_id)
  end

  @doc """
  Changeset for denying a tool use.
  """
  @spec deny_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def deny_changeset(tool_use, attrs) do
    tool_use
    |> cast(attrs, [:denial_reason, :approved_by_id])
    |> put_change(:status, "denied")
    |> put_change(:approved_at, DateTime.utc_now())
  end

  @doc """
  Changeset for starting tool execution.
  """
  @spec executing_changeset(t() | Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def executing_changeset(tool_use) do
    tool_use
    |> change(%{
      status: "executing",
      started_at: DateTime.utc_now()
    })
  end

  @doc """
  Changeset for completing tool execution successfully.
  """
  @spec complete_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def complete_changeset(tool_use, attrs) do
    now = DateTime.utc_now()
    started_at = tool_use.started_at || now
    duration_ms = DateTime.diff(now, started_at, :millisecond)

    tool_use
    |> cast(attrs, [:output, :output_truncated, :file_changes, :exit_code, :stdout, :stderr])
    |> put_change(:status, "completed")
    |> put_change(:completed_at, now)
    |> put_change(:duration_ms, duration_ms)
  end

  @doc """
  Changeset for recording a failed tool execution.
  """
  @spec failure_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def failure_changeset(tool_use, attrs) do
    now = DateTime.utc_now()
    started_at = tool_use.started_at || now
    duration_ms = DateTime.diff(now, started_at, :millisecond)

    tool_use
    |> cast(attrs, [:error_type, :error_message, :exit_code, :stderr])
    |> put_change(:status, "failed")
    |> put_change(:completed_at, now)
    |> put_change(:duration_ms, duration_ms)
  end
end
