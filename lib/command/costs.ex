defmodule Command.Costs do
  @moduledoc """
  The Costs context.

  Tracks API costs and provides reporting.
  """

  import Ecto.Query

  alias Command.Accounts.User
  alias Command.Costs.{CostDailySummary, CostRecord}
  alias Command.Repo

  @doc """
  Records a cost.
  """
  @spec record_cost(User.t(), map()) :: {:ok, CostRecord.t()} | {:error, Ecto.Changeset.t()}
  def record_cost(user, attrs) do
    attrs = Map.put(attrs, :user_id, user.id)

    result =
      %CostRecord{}
      |> CostRecord.create_changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, record} ->
        update_daily_summary(record)
        {:ok, record}

      error ->
        error
    end
  end

  @doc """
  Gets total cost for a user today.
  """
  @spec get_daily_cost(User.t()) :: integer()
  def get_daily_cost(user) do
    today = Date.utc_today()

    CostRecord
    |> where([c], c.user_id == ^user.id and c.day == ^today)
    |> Repo.aggregate(:sum, :cost_cents) || 0
  end

  @doc """
  Gets total cost for a user this week.
  """
  @spec get_weekly_cost(User.t()) :: integer()
  def get_weekly_cost(user) do
    week_start = Date.add(Date.utc_today(), -7)

    CostRecord
    |> where([c], c.user_id == ^user.id and c.day >= ^week_start)
    |> Repo.aggregate(:sum, :cost_cents) || 0
  end

  @doc """
  Gets total cost for a user this month.
  """
  @spec get_monthly_cost(User.t()) :: integer()
  def get_monthly_cost(user) do
    month_start = Date.utc_today() |> Date.beginning_of_month()

    CostRecord
    |> where([c], c.user_id == ^user.id and c.day >= ^month_start)
    |> Repo.aggregate(:sum, :cost_cents) || 0
  end

  @doc """
  Lists daily summaries for a user.
  """
  @spec list_daily_summaries(User.t(), keyword()) :: [CostDailySummary.t()]
  def list_daily_summaries(user, opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    start_date = Date.add(Date.utc_today(), -days)

    CostDailySummary
    |> where([s], s.user_id == ^user.id and s.day >= ^start_date)
    |> order_by([s], desc: s.day)
    |> Repo.all()
  end

  @doc """
  Gets cost breakdown by provider for a user.
  """
  @spec get_cost_by_provider(User.t(), keyword()) :: map()
  def get_cost_by_provider(user, opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    start_date = Date.add(Date.utc_today(), -days)

    CostRecord
    |> where([c], c.user_id == ^user.id and c.day >= ^start_date)
    |> group_by([c], c.provider)
    |> select([c], {c.provider, sum(c.cost_cents)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Gets cost breakdown by model for a user.
  """
  @spec get_cost_by_model(User.t(), keyword()) :: map()
  def get_cost_by_model(user, opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    start_date = Date.add(Date.utc_today(), -days)

    CostRecord
    |> where([c], c.user_id == ^user.id and c.day >= ^start_date)
    |> group_by([c], c.model)
    |> select([c], {c.model, sum(c.cost_cents)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Gets cost summary for a specific day.
  """
  @spec get_daily_summary(User.t(), Date.t()) :: CostDailySummary.t() | nil
  def get_daily_summary(user, date) do
    Repo.get_by(CostDailySummary, user_id: user.id, day: date)
  end

  @doc """
  Regenerates daily summary from cost records.
  """
  @spec regenerate_daily_summary(User.t(), Date.t()) ::
          {:ok, CostDailySummary.t()} | {:error, Ecto.Changeset.t()}
  def regenerate_daily_summary(user, date) do
    records =
      CostRecord
      |> where([c], c.user_id == ^user.id and c.day == ^date)
      |> Repo.all()

    total_cost = Enum.sum(Enum.map(records, & &1.cost_cents))
    total_tokens_in = Enum.sum(Enum.map(records, & &1.tokens_in))
    total_tokens_out = Enum.sum(Enum.map(records, & &1.tokens_out))
    total_requests = length(records)

    cost_by_provider =
      records
      |> Enum.group_by(& &1.provider)
      |> Enum.map(fn {k, v} -> {k, Enum.sum(Enum.map(v, & &1.cost_cents))} end)
      |> Map.new()

    cost_by_model =
      records
      |> Enum.group_by(& &1.model)
      |> Enum.map(fn {k, v} -> {k, Enum.sum(Enum.map(v, & &1.cost_cents))} end)
      |> Map.new()

    cost_by_session =
      records
      |> Enum.filter(& &1.session_id)
      |> Enum.group_by(& &1.session_id)
      |> Enum.map(fn {k, v} -> {k, Enum.sum(Enum.map(v, & &1.cost_cents))} end)
      |> Map.new()

    attrs = %{
      user_id: user.id,
      day: date,
      total_cost_cents: total_cost,
      total_tokens_in: total_tokens_in,
      total_tokens_out: total_tokens_out,
      total_requests: total_requests,
      cost_by_provider: cost_by_provider,
      cost_by_model: cost_by_model,
      cost_by_session: cost_by_session
    }

    case get_daily_summary(user, date) do
      nil ->
        %CostDailySummary{}
        |> CostDailySummary.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> CostDailySummary.changeset(attrs)
        |> Repo.update()
    end
  end

  # Private helpers

  defp update_daily_summary(record) do
    case Repo.get_by(CostDailySummary, user_id: record.user_id, day: record.day) do
      nil ->
        %CostDailySummary{}
        |> CostDailySummary.changeset(%{
          user_id: record.user_id,
          day: record.day
        })
        |> Repo.insert!()
        |> CostDailySummary.increment_changeset(%{
          cost_cents: record.cost_cents,
          tokens_in: record.tokens_in,
          tokens_out: record.tokens_out,
          provider: record.provider,
          model: record.model,
          session_id: record.session_id
        })
        |> Repo.update!()

      summary ->
        summary
        |> CostDailySummary.increment_changeset(%{
          cost_cents: record.cost_cents,
          tokens_in: record.tokens_in,
          tokens_out: record.tokens_out,
          provider: record.provider,
          model: record.model,
          session_id: record.session_id
        })
        |> Repo.update!()
    end
  end
end
