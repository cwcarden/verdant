defmodule VerdantWeb.WeatherLive do
  use VerdantWeb, :live_view
  alias Verdant.Weather

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Weather")
     |> assign(:active_tab, :weather)
     |> assign(:latest, Weather.latest_reading())
     |> assign(:readings, Weather.recent_readings(48))
     |> assign(:fetching, false)
     |> assign(:skip_result, Weather.should_skip_watering?())}
  end

  def handle_event("fetch_weather", _params, socket) do
    socket = assign(socket, :fetching, true)
    send(self(), :do_fetch)
    {:noreply, socket}
  end

  def handle_info(:do_fetch, socket) do
    result = Weather.fetch_from_api()

    socket =
      case result do
        {:ok, _reading} ->
          socket
          |> put_flash(:info, "Weather data updated")
          |> assign(:latest, Weather.latest_reading())
          |> assign(:readings, Weather.recent_readings(48))
          |> assign(:skip_result, Weather.should_skip_watering?())

        {:error, msg} ->
          put_flash(socket, :error, "Failed to fetch weather: #{msg}")
      end

    {:noreply, assign(socket, :fetching, false)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={@active_tab}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold">Weather</h1>
            <p class="text-sm text-base-content/50 mt-0.5">Ambient Weather WS-2000 data</p>
          </div>
          <button
            phx-click="fetch_weather"
            disabled={@fetching}
            class="btn btn-primary btn-sm"
          >
            <.icon
              name={if @fetching, do: "hero-arrow-path", else: "hero-arrow-path"}
              class={["size-4", if(@fetching, do: "animate-spin")]}
            />
            {if @fetching, do: "Fetching...", else: "Fetch Now"}
          </button>
        </div>

        <%!-- Watering skip status --%>
        <% {will_skip, reason} = @skip_result %>
        <div class={["alert shadow-sm", if(will_skip, do: "alert-warning", else: "alert-success")]}>
          <.icon
            name={if will_skip, do: "hero-x-circle", else: "hero-check-circle"}
            class="size-5 shrink-0"
          />
          <div>
            <p class="font-semibold">
              {if will_skip, do: "Watering would be skipped", else: "Conditions OK to water"}
            </p>
            <p class="text-sm opacity-70">
              {if will_skip, do: reason, else: "All weather thresholds are within acceptable range"}
            </p>
          </div>
        </div>

        <%!-- Current conditions --%>
        <%= if @latest do %>
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-5">
              <div class="flex items-start justify-between">
                <div>
                  <h2 class="font-bold text-lg">Current Conditions</h2>
                  <p class="text-xs text-base-content/40">
                    {Calendar.strftime(@latest.recorded_at, "%A %B %d, %Y at %I:%M %p")}
                    {if @latest.station_name, do: "· #{@latest.station_name}"}
                  </p>
                </div>
              </div>

              <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-4 mt-4">
                <.wx_stat
                  label="Temperature"
                  value={"#{round(@latest.temperature_f || 0)}°F"}
                  sub={if @latest.feels_like_f, do: "Feels #{round(@latest.feels_like_f)}°F"}
                  icon="hero-sun"
                  color="text-warning"
                />
                <.wx_stat
                  label="Humidity"
                  value={"#{round(@latest.humidity_pct || 0)}%"}
                  icon="hero-beaker"
                  color="text-info"
                />
                <.wx_stat
                  label="Wind"
                  value={"#{round(@latest.wind_speed_mph || 0)} mph"}
                  sub={if @latest.wind_gust_mph, do: "Gust #{round(@latest.wind_gust_mph)} mph"}
                  icon="hero-arrow-up-circle"
                  color="text-secondary"
                />
                <.wx_stat
                  label="Rain Today"
                  value={"#{@latest.rain_daily_in || 0}\""}
                  sub={if @latest.rain_event_in, do: "Event #{@latest.rain_event_in}\""}
                  icon="hero-cloud"
                  color="text-primary"
                />
                <.wx_stat
                  label="Rain Weekly"
                  value={"#{@latest.rain_weekly_in || 0}\""}
                  icon="hero-calendar"
                  color="text-primary"
                />
                <.wx_stat
                  label="Barometer"
                  value={"#{@latest.pressure_inhg || 0}\""}
                  icon="hero-chart-bar"
                  color="text-neutral"
                />
                <.wx_stat
                  label="UV Index"
                  value={to_string(@latest.uv_index || 0)}
                  icon="hero-sun"
                  color="text-warning"
                />
                <.wx_stat
                  label="Dew Point"
                  value={if @latest.dew_point_f, do: "#{round(@latest.dew_point_f)}°F", else: "—"}
                  icon="hero-eye-dropper"
                  color="text-success"
                />
              </div>
            </div>
          </div>
        <% else %>
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body py-12 items-center text-center">
              <.icon name="hero-cloud" class="size-12 text-base-content/20" />
              <p class="mt-3 font-medium text-base-content/50">No weather data available</p>
              <p class="text-sm text-base-content/30">
                Configure your Ambient Weather API in Settings, then click Fetch Now
              </p>
              <a href={~p"/settings"} class="btn btn-primary btn-sm mt-4">Go to Settings</a>
            </div>
          </div>
        <% end %>

        <%!-- Recent readings table --%>
        <%= if @readings != [] do %>
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-4">
              <h2 class="font-bold">Recent Readings (48h)</h2>
              <div class="overflow-x-auto mt-3">
                <table class="table table-sm">
                  <thead>
                    <tr class="bg-base-200">
                      <th>Time</th>
                      <th>Temp (°F)</th>
                      <th>Humidity</th>
                      <th>Wind (mph)</th>
                      <th>Rain Today</th>
                      <th>UV</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for r <- @readings do %>
                      <tr class="hover">
                        <td class="text-xs whitespace-nowrap">
                          {Calendar.strftime(r.recorded_at, "%m/%d %I:%M %p")}
                        </td>
                        <td>{if r.temperature_f, do: round(r.temperature_f), else: "—"}</td>
                        <td>{if r.humidity_pct, do: "#{round(r.humidity_pct)}%", else: "—"}</td>
                        <td>{if r.wind_speed_mph, do: round(r.wind_speed_mph), else: "—"}</td>
                        <td>{if r.rain_daily_in, do: "#{r.rain_daily_in}\"", else: "—"}</td>
                        <td>{r.uv_index || "—"}</td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :sub, :string, default: nil
  attr :icon, :string, required: true
  attr :color, :string, default: "text-primary"

  defp wx_stat(assigns) do
    ~H"""
    <div class="p-3 bg-base-200 rounded-xl">
      <div class="flex items-center gap-2 mb-1">
        <.icon name={@icon} class={["size-3.5 shrink-0", @color]} />
        <span class="text-xs text-base-content/50 font-medium">{@label}</span>
      </div>
      <p class="text-xl font-bold">{@value}</p>
      <%= if @sub do %>
        <p class="text-xs text-base-content/40 mt-0.5">{@sub}</p>
      <% end %>
    </div>
    """
  end
end
