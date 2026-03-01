defmodule VerdantWeb.ManualLive do
  use VerdantWeb, :live_view
  alias Verdant.{Zones, Watering}

  @refresh_interval 3_000

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh, @refresh_interval)
    end

    zones = Zones.list_zones()
    active_session = Watering.get_active_session()

    {:ok,
     socket
     |> assign(:page_title, "Manual Control")
     |> assign(:active_tab, :manual)
     |> assign(:zones, zones)
     |> assign(:active_session, active_session)
     |> assign(:selected_duration, 10)
     |> assign(:confirming_stop, false)}
  end

  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    active_session = Watering.get_active_session()
    {:noreply, assign(socket, :active_session, active_session)}
  end

  def handle_event("set_duration", %{"duration" => duration}, socket) do
    {:noreply, assign(socket, :selected_duration, String.to_integer(duration))}
  end

  def handle_event("start_zone", %{"zone_id" => zone_id}, socket) do
    zone = Zones.get_zone!(zone_id)
    planned_seconds = socket.assigns.selected_duration * 60

    attrs = %{
      zone_id: zone.id,
      zone_name: zone.name,
      trigger: "manual",
      planned_duration_seconds: planned_seconds
    }

    case Watering.start_session(attrs) do
      {:ok, _session} ->
        {:noreply,
         socket
         |> put_flash(:info, "Started watering #{zone.name}")
         |> assign(:active_session, Watering.get_active_session())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to start watering")}
    end
  end

  def handle_event("stop_watering", _params, socket) do
    case socket.assigns.active_session do
      nil ->
        {:noreply, socket}

      session ->
        case Watering.end_session(session) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Watering stopped")
             |> assign(:active_session, nil)
             |> assign(:confirming_stop, false)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to stop watering")}
        end
    end
  end

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

        <%!-- Active session banner --%>
        <%= if @active_session do %>
          <div class="alert alert-success shadow-sm">
            <.icon name="hero-play-circle" class="size-5 shrink-0" />
            <div class="flex-1">
              <p class="font-semibold">
                Watering: {@active_session.zone_name}
              </p>
              <p class="text-sm opacity-80">
                Running for {div(DateTime.diff(DateTime.utc_now(), @active_session.started_at), 60)} minutes
                <%= if @active_session.planned_duration_seconds do %>
                  · {div(@active_session.planned_duration_seconds, 60)} min planned
                <% end %>
              </p>
            </div>
            <button phx-click="stop_watering" class="btn btn-sm btn-error">
              <.icon name="hero-stop-circle" class="size-4" />
              Stop
            </button>
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
              active_session={@active_session}
              selected_duration={@selected_duration}
            />
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :zone, :any, required: true
  attr :active_session, :any, default: nil
  attr :selected_duration, :integer, required: true

  defp zone_card(assigns) do
    assigns =
      assign(assigns, :is_active,
        assigns.active_session && assigns.active_session.zone_id == assigns.zone.id)
    ~H"""
    <div class={[
      "card shadow-sm transition-all",
      if(@is_active, do: "bg-success/10 border-2 border-success", else: "bg-base-100 border border-base-200")
    ]}>
      <div class="card-body p-4">
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
              ]}></span>
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

        <div class="mt-3">
          <%= if @is_active do %>
            <div class="space-y-2">
              <%= if @active_session.planned_duration_seconds do %>
                <progress
                  class="progress progress-success w-full"
                  value={min(DateTime.diff(DateTime.utc_now(), @active_session.started_at), @active_session.planned_duration_seconds)}
                  max={@active_session.planned_duration_seconds}
                >
                </progress>
              <% end %>
              <button
                phx-click="stop_watering"
                class="btn btn-error btn-sm w-full"
              >
                <.icon name="hero-stop-circle" class="size-4" />
                Stop
              </button>
            </div>
          <% else %>
            <button
              phx-click="start_zone"
              phx-value-zone_id={@zone.id}
              disabled={!@zone.enabled || @active_session != nil}
              class={[
                "btn btn-sm w-full",
                if(@zone.enabled, do: "btn-primary", else: "btn-ghost opacity-50")
              ]}
            >
              <.icon name="hero-play" class="size-4" />
              Run {@selected_duration}m
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
