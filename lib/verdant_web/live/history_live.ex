defmodule VerdantWeb.HistoryLive do
  use VerdantWeb, :live_view
  alias Verdant.{Watering, Settings}

  def mount(_params, _session, socket) do
    limit = Settings.get_integer("history_display_limit", 100)
    sessions = Watering.list_recent_sessions(limit)

    {:ok,
     socket
     |> assign(:page_title, "History")
     |> assign(:active_tab, :history)
     |> assign(:limit, limit)
     |> assign(:sessions, sessions)
     |> assign(:total_minutes, total_minutes(sessions))}
  end

  defp total_minutes(sessions) do
    sessions
    |> Enum.filter(&(!&1.skipped && &1.actual_duration_seconds))
    |> Enum.sum_by(& &1.actual_duration_seconds)
    |> div(60)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={@active_tab}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold">Watering History</h1>
            <p class="text-sm text-base-content/50 mt-0.5">Last {@limit} watering sessions</p>
          </div>
          <div class="stats stats-horizontal shadow-sm bg-base-100">
            <div class="stat p-3">
              <div class="stat-title text-xs">Total Sessions</div>
              <div class="stat-value text-lg">{length(@sessions)}</div>
            </div>
            <div class="stat p-3">
              <div class="stat-title text-xs">Total Runtime</div>
              <div class="stat-value text-lg">{@total_minutes}m</div>
            </div>
          </div>
        </div>

        <div class="card bg-base-100 shadow-sm">
          <div class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr class="bg-base-200">
                  <th>Zone</th>
                  <th>Started</th>
                  <th>Duration</th>
                  <th>Trigger</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                <%= if @sessions == [] do %>
                  <tr>
                    <td colspan="5" class="text-center py-12 text-base-content/40">
                      No watering history yet
                    </td>
                  </tr>
                <% end %>
                <%= for session <- @sessions do %>
                  <tr class="hover">
                    <td>
                      <div>
                        <p class="font-medium">{session.zone_name}</p>
                      </div>
                    </td>
                    <td class="text-sm whitespace-nowrap">
                      {Calendar.strftime(session.started_at, "%b %d, %Y %I:%M %p")}
                    </td>
                    <td class="text-sm">
                      <%= cond do %>
                        <% session.actual_duration_seconds -> %>
                          {div(session.actual_duration_seconds, 60)}m {rem(
                            session.actual_duration_seconds,
                            60
                          )}s
                        <% session.planned_duration_seconds -> %>
                          <span class="text-base-content/40">
                            {div(session.planned_duration_seconds, 60)}m planned
                          </span>
                        <% true -> %>
                          —
                      <% end %>
                    </td>
                    <td>
                      <span class="badge badge-ghost badge-sm capitalize">{session.trigger}</span>
                    </td>
                    <td>
                      <span class={[
                        "badge badge-sm",
                        cond do
                          session.skipped -> "badge-warning"
                          session.ended_at -> "badge-success"
                          true -> "badge-info"
                        end
                      ]}>
                        {cond do
                          session.skipped -> "Skipped"
                          session.ended_at -> "Complete"
                          true -> "Active"
                        end}
                      </span>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
