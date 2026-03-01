defmodule VerdantWeb.DashboardLive do
  use VerdantWeb, :live_view
  alias Verdant.{Zones, Weather, Watering}

  @refresh_interval 5_000

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh, @refresh_interval)
    end

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:active_tab, :dashboard)
     |> load_data()}
  end

  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load_data(socket)}
  end

  defp load_data(socket) do
    zones = Zones.list_zones()
    weather = Weather.latest_reading()
    active_session = Watering.get_active_session()
    today_seconds = Watering.today_usage()
    recent = Watering.list_recent_sessions(5)

    socket
    |> assign(:zones, zones)
    |> assign(:weather, weather)
    |> assign(:active_session, active_session)
    |> assign(:today_minutes, div(today_seconds, 60))
    |> assign(:recent_sessions, recent)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={@active_tab}>
      <div class="space-y-6">
        <%!-- Page header --%>
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold text-base-content">Dashboard</h1>
            <p class="text-sm text-base-content/50 mt-0.5">
              {Calendar.strftime(DateTime.utc_now(), "%A, %B %d %Y")}
            </p>
          </div>
          <div class="flex items-center gap-2">
            <%= if @active_session do %>
              <span class="badge badge-success gap-1 animate-pulse">
                <span class="size-2 rounded-full bg-success-content inline-block"></span>
                Watering Active
              </span>
            <% else %>
              <span class="badge badge-ghost">Idle</span>
            <% end %>
          </div>
        </div>

        <%!-- Stat cards row --%>
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <.stat_card
            label="Active Zone"
            value={if @active_session, do: @active_session.zone_name, else: "—"}
            icon="hero-play-circle"
            color={if @active_session, do: "text-success", else: "text-base-content/30"}
          />
          <.stat_card
            label="Today's Runtime"
            value={"#{@today_minutes}m"}
            icon="hero-clock"
            color="text-primary"
          />
          <.stat_card
            label="Zones"
            value={"#{Enum.count(@zones, & &1.enabled)}/#{length(@zones)}"}
            icon="hero-adjustments-horizontal"
            color="text-secondary"
          />
          <.stat_card
            label="Temperature"
            value={if @weather && @weather.temperature_f, do: "#{round(@weather.temperature_f)}°F", else: "—"}
            icon="hero-sun"
            color="text-warning"
          />
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <%!-- Active watering --%>
          <div class="lg:col-span-2">
            <.active_watering_card session={@active_session} />
          </div>

          <%!-- Weather snapshot --%>
          <div>
            <.weather_card weather={@weather} />
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <%!-- Zone status grid --%>
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-4">
              <h2 class="card-title text-base">Zone Status</h2>
              <div class="grid grid-cols-2 gap-2 mt-2">
                <%= for zone <- @zones do %>
                  <.zone_status_chip zone={zone} active_session={@active_session} />
                <% end %>
              </div>
            </div>
          </div>

          <%!-- Recent activity --%>
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-4">
              <h2 class="card-title text-base">Recent Activity</h2>
              <div class="space-y-2 mt-2">
                <%= if @recent_sessions == [] do %>
                  <p class="text-sm text-base-content/40 py-4 text-center">No watering history yet</p>
                <% else %>
                  <%= for session <- @recent_sessions do %>
                    <.activity_row session={session} />
                  <% end %>
                <% end %>
              </div>
              <div class="mt-3">
                <a href={~p"/history"} class="btn btn-ghost btn-sm w-full">View Full History</a>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :icon, :string, required: true
  attr :color, :string, default: "text-primary"

  defp stat_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body p-4">
        <div class="flex items-start justify-between">
          <div>
            <p class="text-xs text-base-content/50 font-medium uppercase tracking-wide">{@label}</p>
            <p class="text-2xl font-bold mt-1">{@value}</p>
          </div>
          <div class={["p-2 rounded-lg bg-base-200", @color]}>
            <.icon name={@icon} class="size-5" />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :session, :any, default: nil

  defp active_watering_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm h-full">
      <div class="card-body p-4">
        <h2 class="card-title text-base">Active Watering</h2>
        <%= if @session do %>
          <div class="mt-3 space-y-3">
            <div class="flex items-center gap-3">
              <div class="size-12 rounded-full bg-success/10 flex items-center justify-center">
                <.icon name="hero-play-circle" class="size-6 text-success" />
              </div>
              <div>
                <p class="font-semibold text-lg">{@session.zone_name}</p>
                <p class="text-sm text-base-content/50">
                  Started {Calendar.strftime(@session.started_at, "%I:%M %p")}
                </p>
              </div>
            </div>
            <%= if @session.planned_duration_seconds do %>
              <div>
                <div class="flex justify-between text-xs text-base-content/50 mb-1">
                  <span>Progress</span>
                  <span>
                    {div(DateTime.diff(DateTime.utc_now(), @session.started_at), 60)}m /
                    {div(@session.planned_duration_seconds, 60)}m
                  </span>
                </div>
                <progress
                  class="progress progress-success w-full"
                  value={min(DateTime.diff(DateTime.utc_now(), @session.started_at), @session.planned_duration_seconds)}
                  max={@session.planned_duration_seconds}
                >
                </progress>
              </div>
            <% end %>
          </div>
        <% else %>
          <div class="flex flex-col items-center justify-center py-8 text-base-content/30">
            <.icon name="hero-pause-circle" class="size-12" />
            <p class="mt-2 text-sm">No active watering</p>
            <a href={~p"/manual"} class="btn btn-primary btn-sm mt-4">Start Manual Watering</a>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :weather, :any, default: nil

  defp weather_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm h-full">
      <div class="card-body p-4">
        <div class="flex items-center justify-between">
          <h2 class="card-title text-base">Weather</h2>
          <a href={~p"/weather"} class="btn btn-ghost btn-xs">View All</a>
        </div>
        <%= if @weather do %>
          <div class="mt-3 space-y-3">
            <div class="flex items-center gap-2">
              <.icon name="hero-sun" class="size-8 text-warning" />
              <span class="text-3xl font-bold">
                {if @weather.temperature_f, do: "#{round(@weather.temperature_f)}°F", else: "—"}
              </span>
            </div>
            <div class="grid grid-cols-2 gap-2 text-sm">
              <.weather_row icon="hero-beaker" label="Humidity" value={"#{round(@weather.humidity_pct || 0)}%"} />
              <.weather_row icon="hero-arrow-up-circle" label="Wind" value={"#{round(@weather.wind_speed_mph || 0)} mph"} />
              <.weather_row icon="hero-cloud" label="Rain Today" value={"#{@weather.rain_daily_in || 0}\""} />
              <.weather_row icon="hero-eye-dropper" label="Dew Pt" value={if @weather.dew_point_f, do: "#{round(@weather.dew_point_f)}°F", else: "—"} />
            </div>
            <p class="text-xs text-base-content/40">
              Updated {Calendar.strftime(@weather.recorded_at, "%I:%M %p")}
            </p>
          </div>
        <% else %>
          <div class="flex flex-col items-center justify-center py-6 text-base-content/30">
            <.icon name="hero-cloud" class="size-10" />
            <p class="mt-2 text-xs text-center">No weather data<br/>Configure in Settings</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true

  defp weather_row(assigns) do
    ~H"""
    <div class="flex items-center gap-1.5">
      <.icon name={@icon} class="size-3.5 text-base-content/40 shrink-0" />
      <span class="text-base-content/50">{@label}</span>
      <span class="font-medium ml-auto">{@value}</span>
    </div>
    """
  end

  attr :zone, :any, required: true
  attr :active_session, :any, default: nil

  defp zone_status_chip(assigns) do
    assigns = assign(assigns, :is_active,
      assigns.active_session && assigns.active_session.zone_id == assigns.zone.id)
    ~H"""
    <div class={[
      "flex items-center gap-2 p-2 rounded-lg border text-sm",
      cond do
        @is_active -> "border-success bg-success/10 text-success"
        @zone.enabled -> "border-base-300 bg-base-200"
        true -> "border-base-300 bg-base-200 opacity-40"
      end
    ]}>
      <span class={[
        "size-2 rounded-full shrink-0",
        cond do
          @is_active -> "bg-success animate-pulse"
          @zone.enabled -> "bg-base-content/20"
          true -> "bg-base-content/10"
        end
      ]}></span>
      <span class="truncate font-medium">{@zone.name}</span>
    </div>
    """
  end

  attr :session, :any, required: true

  defp activity_row(assigns) do
    ~H"""
    <div class="flex items-center gap-3 py-1.5 border-b border-base-200 last:border-0">
      <div class="size-8 rounded-lg bg-base-200 flex items-center justify-center shrink-0">
        <.icon name="hero-sparkles" class="size-4 text-primary" />
      </div>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-medium truncate">{@session.zone_name}</p>
        <p class="text-xs text-base-content/40">
          {Calendar.strftime(@session.started_at, "%b %d, %I:%M %p")}
          <%= if @session.actual_duration_seconds do %>
            · {div(@session.actual_duration_seconds, 60)}m
          <% end %>
        </p>
      </div>
      <span class={[
        "badge badge-xs",
        if(@session.skipped, do: "badge-warning", else: "badge-success")
      ]}>
        {if @session.skipped, do: "Skipped", else: "Done"}
      </span>
    </div>
    """
  end
end
