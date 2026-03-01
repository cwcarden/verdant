defmodule VerdantWeb.ZonesLive do
  use VerdantWeb, :live_view
  alias Verdant.{Zones, Zones.Zone}

  def mount(_params, _session, socket) do
    zones = Zones.list_zones()

    {:ok,
     socket
     |> assign(:page_title, "Zones")
     |> assign(:active_tab, :zones)
     |> assign(:zones, zones)
     |> assign(:editing_zone, nil)
     |> assign(:form, nil)
     |> assign(:show_new_form, false)}
  end

  def handle_event("edit_zone", %{"id" => id}, socket) do
    zone = Zones.get_zone!(id)
    changeset = Zones.change_zone(zone)

    {:noreply,
     socket
     |> assign(:editing_zone, zone)
     |> assign(:form, to_form(changeset))
     |> assign(:show_new_form, false)}
  end

  def handle_event("new_zone", _params, socket) do
    next_pos = length(socket.assigns.zones) + 1
    changeset = Zones.change_zone(%Zone{}, %{position: next_pos})

    {:noreply,
     socket
     |> assign(:editing_zone, nil)
     |> assign(:form, to_form(changeset))
     |> assign(:show_new_form, true)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_zone, nil)
     |> assign(:form, nil)
     |> assign(:show_new_form, false)}
  end

  def handle_event("save_zone", %{"zone" => params}, socket) do
    result =
      if socket.assigns.editing_zone do
        Zones.update_zone(socket.assigns.editing_zone, params)
      else
        Zones.create_zone(params)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Zone saved")
         |> assign(:zones, Zones.list_zones())
         |> assign(:editing_zone, nil)
         |> assign(:form, nil)
         |> assign(:show_new_form, false)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("toggle_zone", %{"id" => id}, socket) do
    zone = Zones.get_zone!(id)

    case Zones.update_zone(zone, %{enabled: !zone.enabled}) do
      {:ok, _} ->
        {:noreply, assign(socket, :zones, Zones.list_zones())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update zone")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={@active_tab}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold">Zones</h1>
            <p class="text-sm text-base-content/50 mt-0.5">
              Configure irrigation zones and GPIO pins
            </p>
          </div>
          <button phx-click="new_zone" class="btn btn-primary btn-sm">
            <.icon name="hero-plus" class="size-4" /> Add Zone
          </button>
        </div>

        <%!-- New zone form --%>
        <%= if @show_new_form do %>
          <.zone_form form={@form} title="New Zone" zones={@zones} />
        <% end %>

        <%!-- Zone list --%>
        <div class="card bg-base-100 shadow-sm overflow-hidden">
          <div class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr class="bg-base-200">
                  <th class="w-8">#</th>
                  <th>Zone Name</th>
                  <th class="hidden sm:table-cell">GPIO</th>
                  <th class="hidden md:table-cell">Flow Rate</th>
                  <th class="hidden md:table-cell">Heads</th>
                  <th>Enabled</th>
                  <th class="text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                <%= if @zones == [] do %>
                  <tr>
                    <td colspan="7" class="text-center py-8 text-base-content/40">
                      No zones configured yet.
                      <a href="#" phx-click="new_zone" class="link link-primary">
                        Add your first zone
                      </a>
                    </td>
                  </tr>
                <% end %>
                <%= for zone <- @zones do %>
                  <tr class={if @editing_zone && @editing_zone.id == zone.id, do: "bg-primary/5"}>
                    <td class="font-mono text-xs text-base-content/40">{zone.position}</td>
                    <td>
                      <div>
                        <p class="font-semibold">{zone.name}</p>
                        <%= if zone.description && zone.description != "" do %>
                          <p class="text-xs text-base-content/40">{zone.description}</p>
                        <% end %>
                      </div>
                    </td>
                    <td class="hidden sm:table-cell">
                      <span class="badge badge-ghost font-mono">GPIO {zone.gpio_pin}</span>
                    </td>
                    <td class="hidden md:table-cell text-sm">
                      {if zone.flow_rate_gpm > 0, do: "#{zone.flow_rate_gpm} GPM", else: "—"}
                    </td>
                    <td class="hidden md:table-cell text-sm">
                      {if zone.water_heads > 0, do: zone.water_heads, else: "—"}
                    </td>
                    <td>
                      <input
                        type="checkbox"
                        class="toggle toggle-primary toggle-sm"
                        checked={zone.enabled}
                        phx-click="toggle_zone"
                        phx-value-id={zone.id}
                      />
                    </td>
                    <td class="text-right">
                      <button
                        phx-click="edit_zone"
                        phx-value-id={zone.id}
                        class="btn btn-ghost btn-xs"
                      >
                        <.icon name="hero-pencil-square" class="size-4" /> Edit
                      </button>
                    </td>
                  </tr>

                  <%!-- Inline edit row --%>
                  <%= if @editing_zone && @editing_zone.id == zone.id do %>
                    <tr class="bg-primary/5">
                      <td colspan="7" class="p-4">
                        <.zone_form form={@form} title={"Edit: #{zone.name}"} zones={@zones} />
                      </td>
                    </tr>
                  <% end %>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <%!-- GPIO reference card --%>
        <div class="card bg-base-100 shadow-sm">
          <div class="card-body p-4">
            <h3 class="font-semibold text-sm text-base-content/60">GPIO Reference (Raspberry Pi)</h3>
            <p class="text-xs text-base-content/40 mt-1">
              Relay modules typically use GPIO pins 2–9 (BCM numbering).
              Master valve uses GPIO 2, zones 1–7 use GPIO 3–9.
              Pins are pulled LOW to activate.
            </p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :form, :any, required: true
  attr :title, :string, required: true
  attr :zones, :list, required: true

  defp zone_form(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-sm">
      <div class="card-body p-4">
        <h3 class="font-semibold">{@title}</h3>
        <.form for={@form} phx-submit="save_zone" class="mt-3">
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            <div class="form-control">
              <label class="label">
                <span class="label-text text-xs font-semibold">Zone Name *</span>
              </label>
              <.input
                field={@form[:name]}
                class="input input-bordered input-sm"
                placeholder="e.g. Back Yard Upper"
              />
            </div>
            <div class="form-control">
              <label class="label">
                <span class="label-text text-xs font-semibold">Description</span>
              </label>
              <.input
                field={@form[:description]}
                class="input input-bordered input-sm"
                placeholder="Optional notes"
              />
            </div>
            <div class="form-control">
              <label class="label">
                <span class="label-text text-xs font-semibold">GPIO Pin (BCM) *</span>
              </label>
              <.input
                type="number"
                field={@form[:gpio_pin]}
                class="input input-bordered input-sm"
                min="2"
                max="27"
              />
            </div>
            <div class="form-control">
              <label class="label">
                <span class="label-text text-xs font-semibold">Position / Order *</span>
              </label>
              <.input
                type="number"
                field={@form[:position]}
                class="input input-bordered input-sm"
                min="1"
                max="8"
              />
            </div>
            <div class="form-control">
              <label class="label">
                <span class="label-text text-xs font-semibold">Water Heads</span>
              </label>
              <.input
                type="number"
                field={@form[:water_heads]}
                class="input input-bordered input-sm"
                min="0"
                placeholder="0"
              />
            </div>
            <div class="form-control">
              <label class="label">
                <span class="label-text text-xs font-semibold">Flow Rate (GPM)</span>
              </label>
              <.input
                type="number"
                field={@form[:flow_rate_gpm]}
                class="input input-bordered input-sm"
                min="0"
                step="0.1"
                placeholder="0.0"
              />
            </div>
          </div>
          <div class="flex gap-2 mt-4">
            <button type="submit" class="btn btn-primary btn-sm">Save Zone</button>
            <button type="button" phx-click="cancel_edit" class="btn btn-ghost btn-sm">Cancel</button>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
