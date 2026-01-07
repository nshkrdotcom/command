defmodule Command.AI.Cost do
  @moduledoc """
  Schema for recording AI operation costs.

  Tracks per-operation usage details so Command can attribute
  spend back to sessions and workflows.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          session_id: Ecto.UUID.t() | nil,
          workflow_id: Ecto.UUID.t() | nil,
          operation: operation() | nil,
          provider: String.t() | nil,
          model: String.t() | nil,
          tokens_in: non_neg_integer(),
          tokens_out: non_neg_integer(),
          cost_usd: Decimal.t() | nil,
          duration_ms: non_neg_integer() | nil,
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @type operation :: :generate | :embed | :classify | :code_generate

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @operations [:generate, :embed, :classify, :code_generate]

  schema "ai_costs" do
    field :workflow_id, :binary_id
    field :operation, Ecto.Enum, values: @operations
    field :provider, :string
    field :model, :string
    field :tokens_in, :integer, default: 0
    field :tokens_out, :integer, default: 0
    field :cost_usd, :decimal
    field :duration_ms, :integer
    field :metadata, :map, default: %{}

    belongs_to :session, Command.Sessions.Session

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new AI cost entry.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(cost, attrs) do
    cost
    |> cast(attrs, [
      :session_id,
      :workflow_id,
      :operation,
      :provider,
      :model,
      :tokens_in,
      :tokens_out,
      :cost_usd,
      :duration_ms,
      :metadata
    ])
    |> validate_required([:session_id, :operation])
    |> validate_number(:tokens_in, greater_than_or_equal_to: 0)
    |> validate_number(:tokens_out, greater_than_or_equal_to: 0)
    |> validate_number(:cost_usd, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:session_id)
  end
end
