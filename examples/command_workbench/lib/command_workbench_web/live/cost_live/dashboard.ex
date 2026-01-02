defmodule CommandWorkbenchWeb.CostLive.Dashboard do
  use CommandWorkbenchWeb, :live_view

  alias Command.Costs

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if connected?(socket) do
      Command.PubSub.subscribe("user:#{user.id}:costs")
      :timer.send_interval(60_000, self(), :refresh_stats)
    end

    {:ok, load_cost_data(socket, user)}
  end

  defp load_cost_data(socket, user) do
    socket
    |> assign(:page_title, "Cost Dashboard")
    |> assign(:daily_cost, Costs.get_daily_cost(user))
    |> assign(:weekly_cost, Costs.get_weekly_cost(user))
    |> assign(:monthly_cost, Costs.get_monthly_cost(user))
    |> assign(:by_provider, Costs.get_cost_by_provider(user, days: 30))
    |> assign(:by_model, Costs.get_cost_by_model(user, days: 30))
    |> assign(:daily_summaries, Costs.list_daily_summaries(user, days: 14))
  end

  @impl true
  def handle_info(:refresh_stats, socket) do
    {:noreply, load_cost_data(socket, socket.assigns.current_user)}
  end

  def handle_info({Command.PubSub, :cost_recorded, _record}, socket) do
    {:noreply, load_cost_data(socket, socket.assigns.current_user)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Cost Dashboard
    </.header>

    <div class="mt-6 grid grid-cols-1 md:grid-cols-3 gap-6">
      <.stat_card title="Today" cost={@daily_cost} />
      <.stat_card title="This Week" cost={@weekly_cost} />
      <.stat_card title="This Month" cost={@monthly_cost} />
    </div>

    <div class="mt-8 grid grid-cols-1 lg:grid-cols-2 gap-6">
      <div class="panel p-6">
        <h3 class="font-medium mb-4">Cost by Provider (30 days)</h3>
        <div class="space-y-3">
          <div :for={{provider, cost} <- @by_provider} class="flex items-center">
            <div class="w-24 text-sm text-slate-600 capitalize"><%= provider %></div>
            <div class="flex-1">
              <div
                class="h-4 bg-ink-700 rounded"
                style={"width: #{cost_percentage(cost, @by_provider)}%"}
              />
            </div>
            <div class="w-20 text-right text-sm">
              <.cost_display cents={cost} />
            </div>
          </div>
        </div>
      </div>

      <div class="panel p-6">
        <h3 class="font-medium mb-4">Cost by Model (30 days)</h3>
        <div class="space-y-3">
          <div :for={{model, cost} <- Enum.take(@by_model, 5)} class="flex items-center">
            <div class="w-40 text-sm text-slate-600 truncate" title={model}>
              <%= model %>
            </div>
            <div class="flex-1">
              <div
                class="h-4 bg-accent-500 rounded"
                style={"width: #{cost_percentage(cost, @by_model)}%"}
              />
            </div>
            <div class="w-20 text-right text-sm">
              <.cost_display cents={cost} />
            </div>
          </div>
        </div>
      </div>
    </div>

    <div class="mt-8 panel p-6">
      <h3 class="font-medium mb-4">Daily Costs (14 days)</h3>
      <div class="flex items-end gap-1 h-32">
        <div
          :for={summary <- Enum.reverse(@daily_summaries)}
          class="flex-1 bg-accent-500/80 rounded-t hover:bg-accent-500 transition-colors"
          style={"height: #{day_height(summary.total_cost_cents, @daily_summaries)}%"}
          title={"#{summary.day}: $#{summary.total_cost_cents / 100}"}
        />
      </div>
      <div class="flex justify-between mt-2 text-xs text-slate-500">
        <span><%= format_date(List.last(@daily_summaries)) %></span>
        <span><%= format_date(List.first(@daily_summaries)) %></span>
      </div>
    </div>
    """
  end

  defp stat_card(assigns) do
    ~H"""
    <div class="panel p-6">
      <div class="text-sm text-slate-500"><%= @title %></div>
      <div class="mt-2 text-3xl font-semibold">
        <.cost_display cents={@cost} />
      </div>
    </div>
    """
  end

  defp cost_percentage(cost, by_map) do
    max_cost = by_map |> Map.values() |> Enum.max(fn -> 1 end)
    min(100, cost / max_cost * 100)
  end

  defp day_height(cost, summaries) do
    max_cost = summaries |> Enum.map(& &1.total_cost_cents) |> Enum.max(fn -> 1 end)
    max(5, cost / max_cost * 100)
  end

  defp format_date(nil), do: ""
  defp format_date(%{day: day}), do: Calendar.strftime(day, "%b %d")
end
