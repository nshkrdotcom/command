defmodule CommandWorkbenchWeb.WorkflowLive.RunComponent do
  use CommandWorkbenchWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div>
        <div class="text-xs uppercase tracking-wider text-slate-500">Run Status</div>
        <div class="text-sm font-semibold capitalize"><%= @run.status %></div>
      </div>
      <div>
        <div class="text-xs uppercase tracking-wider text-slate-500">Started</div>
        <div class="text-sm font-semibold">
          <%= if @run.started_at, do: Calendar.strftime(@run.started_at, "%b %d, %H:%M"), else: "Pending" %>
        </div>
      </div>
      <div>
        <div class="text-xs uppercase tracking-wider text-slate-500">Cost</div>
        <div class="text-sm font-semibold">$<%= (@run.total_cost_cents || 0) / 100 %></div>
      </div>

      <div>
        <h4 class="text-xs uppercase tracking-wider text-slate-500">Steps</h4>
        <div class="mt-2 space-y-2">
          <div :for={step <- @steps} class="rounded border border-sand-200 p-2">
            <div class="text-sm font-medium"><%= step.step_name %></div>
            <div class="text-xs text-slate-500">
              <%= step.step_type %> · <%= step.status %>
            </div>
          </div>

          <div :if={@steps == []} class="text-sm text-slate-500">
            No steps recorded yet.
          </div>
        </div>
      </div>
    </div>
    """
  end
end
