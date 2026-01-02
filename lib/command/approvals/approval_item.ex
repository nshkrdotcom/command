defmodule Command.Approvals.ApprovalItem do
  @moduledoc """
  Schema for approval queue items.

  Represents pending approval requests for tool executions,
  file writes, shell commands, and workflow steps.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          session_id: Ecto.UUID.t() | nil,
          approval_type: String.t() | nil,
          status: String.t(),
          priority: String.t(),
          title: String.t() | nil,
          description: String.t() | nil,
          payload: map() | nil,
          source_type: String.t() | nil,
          source_id: Ecto.UUID.t() | nil,
          context: map(),
          risk_level: String.t() | nil,
          risk_factors: [String.t()],
          decided_by_id: Ecto.UUID.t() | nil,
          decided_at: DateTime.t() | nil,
          decision_note: String.t() | nil,
          modified_payload: map() | nil,
          expires_at: DateTime.t() | nil,
          timeout_action: String.t(),
          auto_approval_rule_id: Ecto.UUID.t() | nil,
          auto_approval_reason: String.t() | nil,
          notified_at: DateTime.t() | nil,
          notification_channels: [String.t()],
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @approval_types ~w(tool_use file_write shell_command workflow_step custom)
  @priorities ~w(low normal high critical)
  @risk_levels ~w(low medium high critical)
  @timeout_actions ~w(deny approve escalate)
  @source_types ~w(tool_use workflow_step manual)

  schema "approval_items" do
    field :approval_type, :string
    field :status, :string, default: "pending"
    field :priority, :string, default: "normal"
    field :title, :string
    field :description, :string
    field :payload, :map
    field :source_type, :string
    field :source_id, :binary_id
    field :context, :map, default: %{}
    field :risk_level, :string
    field :risk_factors, {:array, :string}, default: []
    field :decided_at, :utc_datetime_usec
    field :decision_note, :string
    field :modified_payload, :map
    field :expires_at, :utc_datetime_usec
    field :timeout_action, :string, default: "deny"
    field :auto_approval_rule_id, :binary_id
    field :auto_approval_reason, :string
    field :notified_at, :utc_datetime_usec
    field :notification_channels, {:array, :string}, default: []
    field :metadata, :map, default: %{}

    belongs_to :user, Command.Accounts.User
    belongs_to :session, Command.Sessions.Session
    belongs_to :decided_by, Command.Accounts.User

    has_many :tool_uses, Command.Agents.ToolUse, foreign_key: :approval_id
    has_many :workflow_steps, Command.Workflows.WorkflowStep, foreign_key: :approval_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new approval item.
  """
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(item, attrs) do
    item
    |> cast(attrs, [
      :user_id,
      :session_id,
      :approval_type,
      :priority,
      :title,
      :description,
      :payload,
      :source_type,
      :source_id,
      :context,
      :risk_level,
      :risk_factors,
      :expires_at,
      :timeout_action,
      :metadata
    ])
    |> validate_required([:user_id, :approval_type, :title, :payload, :source_type])
    |> validate_inclusion(:approval_type, @approval_types)
    |> validate_inclusion(:priority, @priorities)
    |> validate_inclusion(:risk_level, @risk_levels ++ [nil])
    |> validate_inclusion(:timeout_action, @timeout_actions)
    |> validate_inclusion(:source_type, @source_types)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:session_id)
  end

  @doc """
  Changeset for approving an item.
  """
  @spec approve_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def approve_changeset(item, attrs) do
    item
    |> cast(attrs, [:decided_by_id, :decision_note, :modified_payload])
    |> put_change(:status, "approved")
    |> put_change(:decided_at, DateTime.utc_now())
    |> foreign_key_constraint(:decided_by_id)
  end

  @doc """
  Changeset for denying an item.
  """
  @spec deny_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def deny_changeset(item, attrs) do
    item
    |> cast(attrs, [:decided_by_id, :decision_note])
    |> put_change(:status, "denied")
    |> put_change(:decided_at, DateTime.utc_now())
  end

  @doc """
  Changeset for auto-approving an item via a rule.
  """
  @spec auto_approve_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def auto_approve_changeset(item, attrs) do
    item
    |> cast(attrs, [:auto_approval_rule_id, :auto_approval_reason])
    |> put_change(:status, "auto_approved")
    |> put_change(:decided_at, DateTime.utc_now())
  end

  @doc """
  Changeset for marking an item as expired.
  """
  @spec expire_changeset(t() | Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def expire_changeset(item) do
    item
    |> change(%{
      status: "expired",
      decided_at: DateTime.utc_now()
    })
  end

  @doc """
  Changeset for recording notification.
  """
  @spec notification_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def notification_changeset(item, attrs) do
    item
    |> cast(attrs, [:notification_channels])
    |> put_change(:notified_at, DateTime.utc_now())
  end
end
