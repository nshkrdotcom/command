defmodule Command.Costs.CostDailySummary do
  @moduledoc """
  Schema for aggregated daily cost summaries.

  Provides fast access to daily cost totals with breakdowns
  by provider, model, and session.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          day: Date.t() | nil,
          total_cost_cents: integer(),
          total_tokens_in: integer(),
          total_tokens_out: integer(),
          total_requests: integer(),
          cost_by_provider: map(),
          cost_by_model: map(),
          cost_by_session: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cost_daily_summaries" do
    field :day, :date
    field :total_cost_cents, :integer, default: 0
    field :total_tokens_in, :integer, default: 0
    field :total_tokens_out, :integer, default: 0
    field :total_requests, :integer, default: 0
    field :cost_by_provider, :map, default: %{}
    field :cost_by_model, :map, default: %{}
    field :cost_by_session, :map, default: %{}

    belongs_to :user, Command.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating or updating a daily summary.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(summary, attrs) do
    summary
    |> cast(attrs, [
      :user_id,
      :day,
      :total_cost_cents,
      :total_tokens_in,
      :total_tokens_out,
      :total_requests,
      :cost_by_provider,
      :cost_by_model,
      :cost_by_session
    ])
    |> validate_required([:user_id, :day])
    |> validate_number(:total_cost_cents, greater_than_or_equal_to: 0)
    |> unique_constraint([:user_id, :day])
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for incrementing summary values.
  """
  @spec increment_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def increment_changeset(summary, attrs) do
    cost = attrs[:cost_cents] || 0
    tokens_in = attrs[:tokens_in] || 0
    tokens_out = attrs[:tokens_out] || 0

    summary
    |> change(%{
      total_cost_cents: (summary.total_cost_cents || 0) + cost,
      total_tokens_in: (summary.total_tokens_in || 0) + tokens_in,
      total_tokens_out: (summary.total_tokens_out || 0) + tokens_out,
      total_requests: (summary.total_requests || 0) + 1,
      cost_by_provider: update_cost_by_key(summary.cost_by_provider, attrs[:provider], cost),
      cost_by_model: update_cost_by_key(summary.cost_by_model, attrs[:model], cost),
      cost_by_session: update_cost_by_key(summary.cost_by_session, attrs[:session_id], cost)
    })
  end

  defp update_cost_by_key(current_map, nil, _cost), do: current_map || %{}

  defp update_cost_by_key(current_map, key, cost) do
    Map.update(current_map || %{}, key, cost, &(&1 + cost))
  end
end
