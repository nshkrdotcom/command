defmodule Command.Pipelines.AIOperation do
  @moduledoc """
  Schema for AI operations recorded during pipeline execution.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type operation :: :generate | :embed | :classify | :code

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          asset_name: String.t() | nil,
          operation: operation() | nil,
          provider: String.t() | nil,
          model: String.t() | nil,
          tokens_in: non_neg_integer(),
          tokens_out: non_neg_integer(),
          cost_usd: Decimal.t() | nil,
          duration_ms: non_neg_integer() | nil,
          metadata: map(),
          pipeline_run_id: Ecto.UUID.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "command_pipeline_ai_operations" do
    field :asset_name, :string
    field :operation, Ecto.Enum, values: [:generate, :embed, :classify, :code]
    field :provider, :string
    field :model, :string
    field :tokens_in, :integer, default: 0
    field :tokens_out, :integer, default: 0
    field :cost_usd, :decimal, default: Decimal.new("0")
    field :duration_ms, :integer
    field :metadata, :map, default: %{}

    belongs_to :pipeline_run, Command.Pipelines.Execution

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for recording an AI operation.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(op, attrs) do
    op
    |> cast(attrs, [
      :asset_name,
      :operation,
      :provider,
      :model,
      :tokens_in,
      :tokens_out,
      :cost_usd,
      :duration_ms,
      :metadata,
      :pipeline_run_id
    ])
    |> validate_required([:asset_name, :operation, :pipeline_run_id])
    |> foreign_key_constraint(:pipeline_run_id)
  end
end
