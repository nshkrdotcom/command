defmodule Command.Agents.AgentCall do
  @moduledoc """
  Schema for individual LLM API calls.

  Tracks every call to an LLM with full request/response details,
  timing, token usage, and cost tracking.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          session_id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          provider: String.t() | nil,
          model: String.t() | nil,
          status: String.t(),
          prompt_messages: [map()] | nil,
          system_prompt: String.t() | nil,
          response_content: String.t() | nil,
          response_blocks: [map()],
          stop_reason: String.t() | nil,
          tokens_in: integer() | nil,
          tokens_out: integer() | nil,
          cache_tokens_read: integer(),
          cache_tokens_write: integer(),
          cost_cents: integer() | nil,
          started_at: DateTime.t() | nil,
          first_token_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          duration_ms: integer() | nil,
          temperature: float() | nil,
          max_tokens: integer() | nil,
          tools_provided: [String.t()],
          error_type: String.t() | nil,
          error_message: String.t() | nil,
          retry_count: integer(),
          workflow_run_id: Ecto.UUID.t() | nil,
          workflow_step_id: Ecto.UUID.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @providers ~w(anthropic openai google cohere)
  @stop_reasons ~w(end_turn tool_use max_tokens stop_sequence)

  schema "agent_calls" do
    field :provider, :string
    field :model, :string
    field :status, :string, default: "pending"
    field :prompt_messages, {:array, :map}
    field :system_prompt, :string
    field :response_content, :string
    field :response_blocks, {:array, :map}, default: []
    field :stop_reason, :string
    field :tokens_in, :integer
    field :tokens_out, :integer
    field :cache_tokens_read, :integer, default: 0
    field :cache_tokens_write, :integer, default: 0
    field :cost_cents, :integer
    field :started_at, :utc_datetime_usec
    field :first_token_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :duration_ms, :integer
    field :temperature, :float
    field :max_tokens, :integer
    field :tools_provided, {:array, :string}, default: []
    field :error_type, :string
    field :error_message, :string
    field :retry_count, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :session, Command.Sessions.Session
    belongs_to :user, Command.Accounts.User
    belongs_to :workflow_run, Command.Workflows.WorkflowRun
    belongs_to :workflow_step, Command.Workflows.WorkflowStep

    has_many :tool_uses, Command.Agents.ToolUse
    has_one :message, Command.Sessions.Message

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new agent call.
  """
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(call, attrs) do
    call
    |> cast(attrs, [
      :session_id,
      :user_id,
      :provider,
      :model,
      :prompt_messages,
      :system_prompt,
      :temperature,
      :max_tokens,
      :tools_provided,
      :workflow_run_id,
      :workflow_step_id,
      :metadata
    ])
    |> validate_required([:session_id, :user_id, :provider, :model, :prompt_messages])
    |> validate_inclusion(:provider, @providers)
    |> validate_number(:temperature, greater_than_or_equal_to: 0, less_than_or_equal_to: 2)
    |> validate_number(:max_tokens, greater_than: 0)
    |> put_change(:started_at, DateTime.utc_now())
    |> foreign_key_constraint(:session_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for recording streaming start.
  """
  @spec streaming_changeset(t() | Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def streaming_changeset(call) do
    call
    |> change(%{
      status: "streaming",
      first_token_at: DateTime.utc_now()
    })
  end

  @doc """
  Changeset for completing an agent call successfully.
  """
  @spec complete_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def complete_changeset(call, attrs) do
    now = DateTime.utc_now()
    started_at = call.started_at || now

    duration_ms =
      DateTime.diff(now, started_at, :millisecond)

    call
    |> cast(attrs, [
      :response_content,
      :response_blocks,
      :stop_reason,
      :tokens_in,
      :tokens_out,
      :cache_tokens_read,
      :cache_tokens_write,
      :cost_cents
    ])
    |> put_change(:status, "completed")
    |> put_change(:completed_at, now)
    |> put_change(:duration_ms, duration_ms)
    |> validate_inclusion(:stop_reason, @stop_reasons ++ [nil])
  end

  @doc """
  Changeset for recording a failed agent call.
  """
  @spec failure_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def failure_changeset(call, attrs) do
    now = DateTime.utc_now()
    started_at = call.started_at || now
    duration_ms = DateTime.diff(now, started_at, :millisecond)

    call
    |> cast(attrs, [:error_type, :error_message])
    |> put_change(:status, "failed")
    |> put_change(:completed_at, now)
    |> put_change(:duration_ms, duration_ms)
  end

  @doc """
  Changeset for cancelling an agent call.
  """
  @spec cancel_changeset(t() | Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def cancel_changeset(call) do
    now = DateTime.utc_now()
    started_at = call.started_at || now
    duration_ms = DateTime.diff(now, started_at, :millisecond)

    call
    |> change(%{
      status: "cancelled",
      completed_at: now,
      duration_ms: duration_ms
    })
  end

  @doc """
  Changeset for incrementing retry count.
  """
  @spec retry_changeset(t() | Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def retry_changeset(call) do
    call
    |> change(%{
      retry_count: (call.retry_count || 0) + 1,
      status: "pending",
      started_at: DateTime.utc_now()
    })
  end
end
