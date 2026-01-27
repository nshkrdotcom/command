defmodule Command.Approvals.ApprovalRule do
  @moduledoc """
  Schema for auto-approval rules.

  Rules define patterns that can automatically approve or deny
  approval items based on configurable conditions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          status: String.t(),
          approval_type: String.t() | nil,
          tool_names: [String.t()],
          conditions: map() | nil,
          action: String.t() | nil,
          action_note: String.t() | nil,
          max_auto_approvals_per_hour: integer() | nil,
          max_auto_approvals_per_session: integer() | nil,
          current_hour_count: integer(),
          hour_reset_at: DateTime.t() | nil,
          priority: integer(),
          times_triggered: integer(),
          last_triggered_at: DateTime.t() | nil,
          applies_to_sessions: [Ecto.UUID.t()],
          applies_to_workflows: [Ecto.UUID.t()],
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(active disabled)
  @approval_types ~w(tool_use file_write shell_command workflow_step custom * )
  @actions ~w(approve deny require_review)

  schema "approval_rules" do
    field :name, :string
    field :description, :string
    field :status, :string, default: "active"
    field :approval_type, :string
    field :tool_names, {:array, :string}, default: []
    field :conditions, :map
    field :action, :string
    field :action_note, :string
    field :max_auto_approvals_per_hour, :integer
    field :max_auto_approvals_per_session, :integer
    field :current_hour_count, :integer, default: 0
    field :hour_reset_at, :utc_datetime_usec
    field :priority, :integer, default: 0
    field :times_triggered, :integer, default: 0
    field :last_triggered_at, :utc_datetime_usec
    field :applies_to_sessions, {:array, :binary_id}, default: []
    field :applies_to_workflows, {:array, :binary_id}, default: []
    field :metadata, :map, default: %{}

    belongs_to :user, Command.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new approval rule.
  """
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(rule, attrs) do
    rule
    |> cast(attrs, [
      :user_id,
      :name,
      :description,
      :approval_type,
      :tool_names,
      :conditions,
      :action,
      :action_note,
      :max_auto_approvals_per_hour,
      :max_auto_approvals_per_session,
      :priority,
      :applies_to_sessions,
      :applies_to_workflows,
      :metadata
    ])
    |> validate_required([:user_id, :name, :approval_type, :conditions, :action])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_inclusion(:approval_type, @approval_types)
    |> validate_inclusion(:action, @actions)
    |> validate_number(:priority, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for updating a rule.
  """
  @spec update_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def update_changeset(rule, attrs) do
    rule
    |> cast(attrs, [
      :name,
      :description,
      :tool_names,
      :conditions,
      :action,
      :action_note,
      :max_auto_approvals_per_hour,
      :max_auto_approvals_per_session,
      :priority,
      :applies_to_sessions,
      :applies_to_workflows,
      :metadata
    ])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_inclusion(:action, @actions)
    |> validate_number(:priority, greater_than_or_equal_to: 0)
  end

  @doc """
  Changeset for updating rule status.
  """
  @spec status_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def status_changeset(rule, attrs) do
    rule
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end

  @doc """
  Changeset for recording a rule trigger.
  """
  @spec trigger_changeset(t() | Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def trigger_changeset(rule) do
    now = DateTime.utc_now()

    {count, reset_at} =
      if rule.hour_reset_at && DateTime.compare(now, rule.hour_reset_at) == :lt do
        {(rule.current_hour_count || 0) + 1, rule.hour_reset_at}
      else
        {1, DateTime.add(now, 3600, :second)}
      end

    rule
    |> change(%{
      times_triggered: (rule.times_triggered || 0) + 1,
      last_triggered_at: now,
      current_hour_count: count,
      hour_reset_at: reset_at
    })
  end
end
