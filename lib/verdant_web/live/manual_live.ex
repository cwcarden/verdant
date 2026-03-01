defmodule VerdantWeb.ManualLive do
  use VerdantWeb, :live_view
  alias Verdant.{Zones, Watering, Irrigation}

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Irrigation.subscribe()
    end

    zones = Zones.list_zones()
    active_sessions = Watering.list_active_sessions()

    {:ok,
     socket
     |> assign(:page_title, "Manual Control")
     |> assign(:active_tab, :manual)
     |> assign(:zones, zones)
     |> assign(:active_sessions, active_sessions)
     |> assign(:selected_duration, 10)
     # Zone struct stored here when user requests a concurrent run confirmation.
     |> assign(:confirming_zone, nil)}
  end

  # ── PubSub handlers ──────────────────────────────────────────────────────────

  def handle_info({:watering_started, _info}, socket) do
    {:noreply, assign(socket, :active_sessions, Watering.list_active_sessions())}
  end

  def handle_info({:zone_complete, _info}, socket) do
    {:noreply, assign(socket, :active_sessions, Watering.list_active_sessions())}
  end

  def handle_info({:watering_stopped, _info}, socket) do
    {:noreply, assign(socket, :active_sessions, Watering.list_active_sessions())}
  end

  def handle_info({:schedule_complete, _info}, socket) do
    {:noreply, assign(socket, :active_sessions, Watering.list_active_sessions())}
  end

  # ── Event handlers ────────────────────────────────────────────────────────────

  def handle_event("set_duration", %{"duration" => duration}, socket) do
    {:noreply, assign(socket, :selected_duration, String.to_integer(duration))}
  end

  # User clicked "Run Xm" on a zone card.
  # If other zones are running, stash this zone and show a confirmation UI
  # instead of starting immediately (more reliable than phx-confirm attribute).
  def handle_event("start_zone", %{"zone_id" => zone_id}, socket) do
    zone = Zones.get_zone!(zone_id)

    if socket.assigns.active_sessions != [] do
      # Show inline confirmation inside the zone card.
      {:noreply, assign(socket, :confirming_zone, zone)}
    else
      do_start_zone(zone, socket)
    end
  end

  # User clicked "Yes, run concurrently" in the confirmation UI.
  def handle_event("confirm_start_zone", _params, socket) do
    zone = socket.assigns.confirming_zone
    socket = assign(socket, :confirming_zone, nil)
    do_start_zone(zone, socket)
  end

  # User clicked "Cancel" in the confirmation UI.
  def handle_event("cancel_start_zone", _params, socket) do
    {:noreply, assign(socket, :confirming_zone, nil)}
  end

  def handle_event("stop_zone", %{"zone_id" => zone_id}, socket) do
    zone_id = String.to_integer(zone_id)

    case Irrigation.stop_zone(zone_id) do
      :ok ->
        zone_name =
          socket.assigns.active_sessions
          |> Enum.find(&(&1.zone_id == zone_id))
          |> then(fn s -> if s, do: s.zone_name, else: "Zone" end)

        {:noreply,
         socket
         |> put_flash(:info, "Stopped #{zone_name}")
         |> assign(:active_sessions, Watering.list_active_sessions())}

      {:error, :not_found} ->
        # Zone not found in the Runner — likely an orphaned DB session from a
        # previous app restart.  End it directly in the DB so the UI clears.
        socket.assigns.active_sessions
        |> Enum.filter(&(&1.zone_id == zone_id))
        |> Enum.each(&Watering.end_session/1)

        {:noreply, assign(socket, :active_sessions, Watering.list_active_sessions())}
    end
  end

  def handle_event("stop_all", _params, socket) do
    Irrigation.stop_all()

    {:noreply,
     socket
     |> put_flash(:info, "All watering stopped")
     |> assign(:active_sessions, [])
     |> assign(:confirming_zone, nil)}
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp do_start_zone(zone, socket) do
    planned_seconds = socket.assigns.selected_duration * 60

    case Irrigation.start_zone(zone, planned_seconds) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Started #{zone.name}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start: #{inspect(reason)}")}
    end
  end

  # ── Render ────────────────────────────────────────────────────────────────────

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={@active_tab}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold">Manual Control</h1>
            <p class="text-sm text-base-content/50 mt-0.5">Start individual zones manually</p>
          </div>
        </div>

        <%!-- Active sessions banner --%>
        <%= if @active_sessions != [] do %>
          <div class="card bg-success/10 border border-success shadow-sm">
            <div class="card-body p-4">
              <div class="flex items-center justify-between mb-3">
                <div class="flex items-center gap-2">
                  <.icon name="hero-play-circle" class="size-5 text-success shrink-0" />
                  <span class="font-semibold">
                    {length(@active_sessions)} zone{if length(@active_sessions) > 1, do: "s"} running
                  </span>
                </div>
                <button phx-click="stop_all" class="btn btn-sm btn-error">
                  <.icon name="hero-stop-circle" class="size-4" /> Stop All
                </button>
              </div>
              <div class="space-y-2">
                <%= for session <- @active_sessions do %>
                  <div class="flex items-center justify-between gap-3 bg-base-100/60 rounded-lg px-3 py-2">
                    <div class="flex-1 min-w-0">
                      <p class="font-medium text-sm truncate">{session.zone_name}</p>
                      <p class="text-xs text-base-content/50">
                        Running {div(DateTime.diff(DateTime.utc_now(), session.started_at), 60)}m
                        <%= if session.planned_duration_seconds do %>
                          · {div(session.planned_duration_seconds, 60)}m planned
                        <% end %>
                      </p>
                    </div>
                    <button
                      phx-click="stop_zone"
                      phx-value-zone_id={session.zone_id}
                      class="btn btn-xs btn-error btn-outline shrink-0"
                    >
                      Stop
                    </button>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Duration selector --%>
        <div class="card bg-base-100 shadow-sm">
          <div class="card-body p-4">
            <h2 class="font-semibold text-base mb-3">Duration</h2>
            <div class="flex flex-wrap gap-2">
              <%= for mins <- [5, 10, 15, 20, 30, 45, 60] do %>
                <button
                  phx-click="set_duration"
                  phx-value-duration={mins}
                  class={[
                    "btn btn-sm",
                    if(@selected_duration == mins, do: "btn-primary", else: "btn-ghost")
                  ]}
                >
                  {mins}m
                </button>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Zone cards --%>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          <%= for zone <- @zones do %>
            <.zone_card
              zone={zone}
              active_sessions={@active_sessions}
              selected_duration={@selected_duration}
              confirming_zone={@confirming_zone}
            />
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ── Components ────────────────────────────────────────────────────────────────

  attr :zone, :any, required: true
  attr :active_sessions, :list, default: []
  attr :selected_duration, :integer, required: true
  attr :confirming_zone, :any, default: nil

  defp zone_card(assigns) do
    assigns =
      assigns
      |> assign(:is_active, Enum.any?(assigns.active_sessions, &(&1.zone_id == assigns.zone.id)))
      |> assign(
        :active_session,
        Enum.find(assigns.active_sessions, &(&1.zone_id == assigns.zone.id))
      )
      |> assign(
        :confirming,
        assigns.confirming_zone != nil && assigns.confirming_zone.id == assigns.zone.id
      )
      |> assign(:running_others, Enum.reject(assigns.active_sessions, &(&1.zone_id == assigns.zone.id)))

    ~H"""
    <div class={[
      "card shadow-sm transition-all",
      cond do
        @is_active -> "bg-success/10 border-2 border-success"
        @confirming -> "bg-warning/10 border-2 border-warning"
        true -> "bg-base-100 border border-base-200"
      end
    ]}>
      <div class="card-body p-4">
        <%!-- Card header --%>
        <div class="flex items-start justify-between gap-2">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2">
              <span class={[
                "size-2.5 rounded-full shrink-0",
                cond do
                  @is_active -> "bg-success animate-pulse"
                  @zone.enabled -> "bg-base-content/20"
                  true -> "bg-error/40"
                end
              ]}>
              </span>
              <h3 class="font-semibold text-base truncate">{@zone.name}</h3>
            </div>
            <%= if @zone.description && @zone.description != "" do %>
              <p class="text-xs text-base-content/50 mt-0.5 ml-4">{@zone.description}</p>
            <% end %>
            <div class="flex items-center gap-3 mt-2 ml-4 text-xs text-base-content/40">
              <span>GPIO {String.pad_leading(to_string(@zone.gpio_pin), 2, "0")}</span>
              <%= if @zone.flow_rate_gpm > 0 do %>
                <span>{@zone.flow_rate_gpm} GPM</span>
              <% end %>
            </div>
          </div>
          <%= if @is_active do %>
            <span class="badge badge-success badge-sm">Active</span>
          <% end %>
        </div>

        <%!-- Action area --%>
        <div class="mt-3">
          <%= cond do %>
            <% @is_active && @active_session -> %>
              <%!-- Zone is running — show progress + stop button --%>
              <div class="space-y-2">
                <%= if @active_session.planned_duration_seconds do %>
                  <progress
                    class="progress progress-success w-full"
                    value={
                      min(
                        DateTime.diff(DateTime.utc_now(), @active_session.started_at),
                        @active_session.planned_duration_seconds
                      )
                    }
                    max={@active_session.planned_duration_seconds}
                  >
                  </progress>
                <% end %>
                <button
                  phx-click="stop_zone"
                  phx-value-zone_id={@active_session.zone_id}
                  class="btn btn-error btn-sm w-full"
                >
                  <.icon name="hero-stop-circle" class="size-4" /> Stop
                </button>
              </div>
            <% @confirming -> %>
              <%!-- User asked to run this zone while others are active — confirm --%>
              <div class="space-y-2">
                <p class="text-xs text-warning font-medium leading-snug">
                  {concurrent_warning(@running_others)} — run {@zone.name} at the same time?
                </p>
                <div class="flex gap-2">
                  <button phx-click="confirm_start_zone" class="btn btn-warning btn-sm flex-1">
                    Yes, run concurrently
                  </button>
                  <button phx-click="cancel_start_zone" class="btn btn-ghost btn-sm">
                    Cancel
                  </button>
                </div>
              </div>
            <% true -> %>
              <%!-- Zone is idle — show run button --%>
              <button
                phx-click="start_zone"
                phx-value-zone_id={@zone.id}
                disabled={!@zone.enabled}
                class={[
                  "btn btn-sm w-full",
                  if(@zone.enabled, do: "btn-primary", else: "btn-ghost opacity-50")
                ]}
              >
                <.icon name="hero-play" class="size-4" /> Run {@selected_duration}m
              </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Returns a short human-readable list of zone names for the concurrent warning.
  defp concurrent_warning([one]), do: "#{one.zone_name} is already running"

  defp concurrent_warning(many) do
    names = Enum.map_join(many, ", ", & &1.zone_name)
    "#{names} are already running"
  end
end
