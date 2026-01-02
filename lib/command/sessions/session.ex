defmodule Command.Sessions.Session do
  @moduledoc """
  Schema for agent work sessions.

  Sessions are persistent, resumable contexts for agent work. They can be
  named, branched, and track full conversation history with cost aggregation.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          purpose: String.t() | nil,
          slug: String.t() | nil,
          status: String.t(),
          parent_session_id: Ecto.UUID.t() | nil,
          forked_at_message_id: Ecto.UUID.t() | nil,
          message_count: integer(),
          total_tokens_in: integer(),
          total_tokens_out: integer(),
          total_cost_cents: integer(),
          total_duration_ms: integer(),
          default_agent: String.t() | nil,
          default_model: String.t() | nil,
          system_prompt: String.t() | nil,
          temperature: float() | nil,
          max_tokens: integer() | nil,
          linked_index_ids: [Ecto.UUID.t()],
          linked_workflow_ids: [Ecto.UUID.t()],
          metadata: map(),
          tags: [String.t()],
          git_context: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(active paused completed archived)
  @agents ~w(claude codex gemini)

  schema "sessions" do
    field :name, :string
    field :purpose, :string
    field :slug, :string
    field :status, :string, default: "active"
    field :forked_at_message_id, :binary_id
    field :message_count, :integer, default: 0
    field :total_tokens_in, :integer, default: 0
    field :total_tokens_out, :integer, default: 0
    field :total_cost_cents, :integer, default: 0
    field :total_duration_ms, :integer, default: 0
    field :default_agent, :string
    field :default_model, :string
    field :system_prompt, :string
    field :temperature, :float
    field :max_tokens, :integer
    field :linked_index_ids, {:array, :binary_id}, default: []
    field :linked_workflow_ids, {:array, :binary_id}, default: []
    field :metadata, :map, default: %{}
    field :tags, {:array, :string}, default: []
    field :git_context, :map, default: %{}

    belongs_to :user, Command.Accounts.User
    belongs_to :parent_session, Command.Sessions.Session

    has_many :messages, Command.Sessions.Message
    has_many :agent_calls, Command.Agents.AgentCall
    has_many :tool_uses, Command.Agents.ToolUse
    has_many :approval_items, Command.Approvals.ApprovalItem
    has_many :artifacts, Command.Artifacts.Artifact
    has_many :cost_records, Command.Costs.CostRecord
    has_many :child_sessions, Command.Sessions.Session, foreign_key: :parent_session_id
    has_many :workflow_runs, Command.Workflows.WorkflowRun

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new session.
  """
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(session, attrs) do
    session
    |> cast(attrs, [
      :name,
      :purpose,
      :slug,
      :user_id,
      :parent_session_id,
      :forked_at_message_id,
      :default_agent,
      :default_model,
      :system_prompt,
      :temperature,
      :max_tokens,
      :linked_index_ids,
      :linked_workflow_ids,
      :metadata,
      :tags,
      :git_context
    ])
    |> validate_required([:name, :user_id])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:default_agent, @agents ++ [nil])
    |> validate_number(:temperature, greater_than_or_equal_to: 0, less_than_or_equal_to: 2)
    |> validate_number(:max_tokens, greater_than: 0)
    |> maybe_generate_slug()
    |> unique_constraint([:user_id, :slug])
  end

  @doc """
  Changeset for updating session status.
  """
  @spec status_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def status_changeset(session, attrs) do
    session
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end

  @doc """
  Changeset for updating session configuration.
  """
  @spec config_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def config_changeset(session, attrs) do
    session
    |> cast(attrs, [
      :default_agent,
      :default_model,
      :system_prompt,
      :temperature,
      :max_tokens,
      :linked_index_ids,
      :linked_workflow_ids
    ])
    |> validate_inclusion(:default_agent, @agents ++ [nil])
    |> validate_number(:temperature, greater_than_or_equal_to: 0, less_than_or_equal_to: 2)
    |> validate_number(:max_tokens, greater_than: 0)
  end

  @doc """
  Changeset for updating session stats (usually done via triggers or updates).
  """
  @spec stats_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def stats_changeset(session, attrs) do
    session
    |> cast(attrs, [
      :message_count,
      :total_tokens_in,
      :total_tokens_out,
      :total_cost_cents,
      :total_duration_ms
    ])
  end

  @doc """
  Changeset for updating tags and metadata.
  """
  @spec metadata_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def metadata_changeset(session, attrs) do
    session
    |> cast(attrs, [:metadata, :tags, :git_context])
  end

  defp maybe_generate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        name = get_field(changeset, :name) || ""

        slug =
          name
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9\s-]/, "")
          |> String.replace(~r/\s+/, "-")
          |> String.slice(0, 50)

        put_change(changeset, :slug, slug)

      _ ->
        changeset
    end
  end
end
