defmodule Command.Costs.CostRecord do
  @moduledoc """
  Schema for detailed cost tracking of API calls.

  Records every API call cost with token breakdown and
  provider-specific pricing information.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          source_type: String.t() | nil,
          source_id: Ecto.UUID.t() | nil,
          session_id: Ecto.UUID.t() | nil,
          workflow_run_id: Ecto.UUID.t() | nil,
          provider: String.t() | nil,
          service: String.t() | nil,
          model: String.t() | nil,
          tokens_in: integer(),
          tokens_out: integer(),
          cache_tokens_read: integer(),
          cache_tokens_write: integer(),
          units: Decimal.t() | nil,
          unit_type: String.t() | nil,
          cost_cents: integer() | nil,
          price_per_million_in: integer() | nil,
          price_per_million_out: integer() | nil,
          incurred_at: DateTime.t() | nil,
          day: Date.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @source_types ~w(agent_call embedding tool_execution)
  @providers ~w(anthropic openai google cohere)
  @services ~w(chat embedding image speech)

  schema "cost_records" do
    field :source_type, :string
    field :source_id, :binary_id
    field :provider, :string
    field :service, :string
    field :model, :string
    field :tokens_in, :integer, default: 0
    field :tokens_out, :integer, default: 0
    field :cache_tokens_read, :integer, default: 0
    field :cache_tokens_write, :integer, default: 0
    field :units, :decimal
    field :unit_type, :string
    field :cost_cents, :integer
    field :price_per_million_in, :integer
    field :price_per_million_out, :integer
    field :incurred_at, :utc_datetime_usec
    field :day, :date
    field :metadata, :map, default: %{}

    belongs_to :user, Command.Accounts.User
    belongs_to :session, Command.Sessions.Session
    belongs_to :workflow_run, Command.Workflows.WorkflowRun

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new cost record.
  """
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(record, attrs) do
    now = DateTime.utc_now()
    today = DateTime.to_date(now)

    record
    |> cast(attrs, [
      :user_id,
      :source_type,
      :source_id,
      :session_id,
      :workflow_run_id,
      :provider,
      :service,
      :model,
      :tokens_in,
      :tokens_out,
      :cache_tokens_read,
      :cache_tokens_write,
      :units,
      :unit_type,
      :cost_cents,
      :price_per_million_in,
      :price_per_million_out,
      :incurred_at,
      :metadata
    ])
    |> validate_required([
      :user_id,
      :source_type,
      :source_id,
      :provider,
      :service,
      :model,
      :cost_cents
    ])
    |> validate_inclusion(:source_type, @source_types)
    |> validate_inclusion(:provider, @providers)
    |> validate_inclusion(:service, @services)
    |> validate_number(:cost_cents, greater_than_or_equal_to: 0)
    |> put_default(:incurred_at, now)
    |> put_day(today)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:session_id)
  end

  defp put_default(changeset, field, default) do
    case get_field(changeset, field) do
      nil -> put_change(changeset, field, default)
      _ -> changeset
    end
  end

  defp put_day(changeset, default_day) do
    incurred_at = get_field(changeset, :incurred_at)

    day =
      if incurred_at do
        DateTime.to_date(incurred_at)
      else
        default_day
      end

    put_change(changeset, :day, day)
  end
end
