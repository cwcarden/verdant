defmodule VerdantWeb.SchedulesLive do
  use VerdantWeb, :live_view
  alias Verdant.{Schedules, Zones}

  @day_names ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

  def mount(_params, _session, socket) do
    schedules = Schedules.list_schedules()
    zones = Zones.list_zones()

    {:ok,
     socket
     |> assign(:page_title, "Schedules")
     |> assign(:active_tab, :schedules)
     |> assign(:schedules, schedules)
     |> assign(:zones, zones)
     |> assign(:editing_schedule, nil)
     |> assign(:form, nil)
     |> assign(:creating, false)
     |> assign(:new_form, nil)}
  end

  def handle_event("edit_schedule", %{"id" => id}, socket) do
    schedule = Schedules.get_schedule!(id)
    changeset = Schedules.change_schedule(schedule)

    {:noreply,
     socket
     |> assign(:editing_schedule, schedule)
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_schedule, nil)
     |> assign(:form, nil)}
  end

  def handle_event("new_schedule", _params, socket) do
    # Pre-select every day so a new schedule is immediately functional
    changeset = Schedules.change_schedule(%Verdant.Schedules.Schedule{days_of_week: "0,1,2,3,4,5,6"})

    {:noreply,
     socket
     |> assign(:creating, true)
     |> assign(:editing_schedule, nil)
     |> assign(:form, nil)
     |> assign(:new_form, to_form(changeset))}
  end

  def handle_event("cancel_create", _params, socket) do
    {:noreply,
     socket
     |> assign(:creating, false)
     |> assign(:new_form, nil)}
  end

  def handle_event("create_schedule", %{"schedule" => params}, socket) do
    params =
      case Map.get(params, "days_of_week") do
        days when is_list(days) -> Map.put(params, "days_of_week", Enum.join(days, ","))
        nil -> Map.put(params, "days_of_week", "")
        _ -> params
      end

    case Schedules.create_schedule(params) do
      {:ok, _new_schedule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Schedule created")
         |> assign(:schedules, Schedules.list_schedules())
         |> assign(:creating, false)
         |> assign(:new_form, nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :new_form, to_form(changeset))}
    end
  end

  def handle_event("delete_schedule", %{"id" => id}, socket) do
    schedule = Schedules.get_schedule!(id)

    case Schedules.delete_schedule(schedule) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Schedule deleted")
         |> assign(:schedules, Schedules.list_schedules())
         |> assign(:editing_schedule, nil)
         |> assign(:form, nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete schedule")}
    end
  end

  def handle_event("toggle_schedule", %{"id" => id}, socket) do
    schedule = Schedules.get_schedule!(id)

    case Schedules.update_schedule(schedule, %{enabled: !schedule.enabled}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           if(schedule.enabled, do: "Schedule disabled", else: "Schedule enabled")
         )
         |> assign(:schedules, Schedules.list_schedules())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update schedule")}
    end
  end

  def handle_event("save_schedule", %{"schedule" => params}, socket) do
    schedule = socket.assigns.editing_schedule

    # HTML sends days checkboxes as a list (["0","2","3"]) when checked, or
    # omits the key entirely when nothing is checked.  Ecto's :string cast
    # can't handle a list, so we normalise it to a comma-separated string here.
    params =
      case Map.get(params, "days_of_week") do
        days when is_list(days) -> Map.put(params, "days_of_week", Enum.join(days, ","))
        nil -> Map.put(params, "days_of_week", "")
        _ -> params
      end

    case Schedules.update_schedule(schedule, params) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Schedule saved")
         |> assign(:schedules, Schedules.list_schedules())
         |> assign(:editing_schedule, nil)
         |> assign(:form, nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event(
        "update_zone_runtime",
        %{"schedule_id" => sid, "zone_id" => zid, "value" => rt},
        socket
      ) do
    Schedules.upsert_schedule_zone(%{
      schedule_id: String.to_integer(sid),
      zone_id: String.to_integer(zid),
      runtime_seconds: String.to_integer(rt) * 60,
      enabled: true
    })

    {:noreply, assign(socket, :schedules, Schedules.list_schedules())}
  end

  def handle_event(
        "toggle_zone_in_schedule",
        %{"schedule_id" => sid, "zone_id" => zid, "enabled" => en},
        socket
      ) do
    schedule = Schedules.get_schedule!(sid)
    existing = Enum.find(schedule.schedule_zones, &(&1.zone_id == String.to_integer(zid)))

    attrs = %{
      schedule_id: String.to_integer(sid),
      zone_id: String.to_integer(zid),
      enabled: en == "true",
      runtime_seconds: if(existing, do: existing.runtime_seconds, else: 600)
    }

    Schedules.upsert_schedule_zone(attrs)
    {:noreply, assign(socket, :schedules, Schedules.list_schedules())}
  end

  defp day_selected?(schedule, day_index) do
    schedule.days_of_week
    |> String.split(",", trim: true)
    |> Enum.member?(to_string(day_index))
  end

  defp zone_in_schedule(schedule, zone_id) do
    Enum.find(schedule.schedule_zones, &(&1.zone_id == zone_id))
  end

  def render(assigns) do
    assigns = assign(assigns, :day_names, @day_names)

    ~H"""
    <Layouts.app flash={@flash} active_tab={@active_tab}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold">Schedules</h1>
            <p class="text-sm text-base-content/50 mt-0.5">Configure automated watering schedules</p>
          </div>
          <button phx-click="new_schedule" class="btn btn-primary btn-sm gap-1.5">
            <.icon name="hero-plus" class="size-4" /> New Schedule
          </button>
        </div>

        <%!-- New schedule create form --%>
        <%= if @creating do %>
          <div class="card bg-base-100 shadow-sm border-2 border-primary/30">
            <div class="card-body p-5">
              <h2 class="font-bold text-lg">New Schedule</h2>
              <.form for={@new_form} phx-submit="create_schedule">
                <div class="space-y-3 mt-2">
                  <div>
                    <label class="label label-text text-xs">Name</label>
                    <.input field={@new_form[:name]} class="input input-bordered input-sm w-full" placeholder="e.g. Morning Run" />
                  </div>
                  <div>
                    <label class="label label-text text-xs">Description (optional)</label>
                    <.input field={@new_form[:label]} class="input input-bordered input-sm w-full" placeholder="e.g. Front yard zones" />
                  </div>
                  <div>
                    <label class="label label-text text-xs">Start Time</label>
                    <.input type="time" field={@new_form[:start_time]} class="input input-bordered input-sm w-full" />
                  </div>
                  <div>
                    <label class="label label-text text-xs">Days</label>
                    <div class="flex gap-1.5 flex-wrap">
                      <%= for {name, idx} <- Enum.with_index(@day_names) do %>
                        <label class="cursor-pointer">
                          <input
                            type="checkbox"
                            class="hidden peer"
                            name="schedule[days_of_week][]"
                            value={idx}
                            checked={day_selected?(@new_form.source.data, idx)}
                          />
                          <span class="w-9 h-9 rounded-full flex items-center justify-center text-xs font-semibold bg-base-200 text-base-content/40 peer-checked:bg-primary peer-checked:text-primary-content cursor-pointer select-none">
                            {String.slice(name, 0, 2)}
                          </span>
                        </label>
                      <% end %>
                    </div>
                  </div>
                  <div class="flex gap-2 mt-2">
                    <button type="submit" class="btn btn-primary btn-sm flex-1">Create Schedule</button>
                    <button type="button" phx-click="cancel_create" class="btn btn-ghost btn-sm">Cancel</button>
                  </div>
                </div>
              </.form>
            </div>
          </div>
        <% end %>

        <div class="grid grid-cols-1 xl:grid-cols-2 gap-6">
          <%= for schedule <- @schedules do %>
            <.schedule_card
              schedule={schedule}
              zones={@zones}
              day_names={@day_names}
              editing={@editing_schedule && @editing_schedule.id == schedule.id}
              form={if @editing_schedule && @editing_schedule.id == schedule.id, do: @form}
            />
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :schedule, :any, required: true
  attr :zones, :list, required: true
  attr :day_names, :list, required: true
  attr :editing, :boolean, default: false
  attr :form, :any, default: nil

  defp schedule_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body p-5">
        <%!-- Header --%>
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <div class={[
              "size-10 rounded-xl flex items-center justify-center font-bold text-lg",
              if(@schedule.enabled,
                do: "bg-primary text-primary-content",
                else: "bg-base-200 text-base-content/30"
              )
            ]}>
              {String.slice(@schedule.name, 0, 1)}
            </div>
            <div>
              <h2 class="font-bold">{@schedule.name}</h2>
              <p class="text-xs text-base-content/50">
                {if @schedule.label && @schedule.label != "",
                  do: @schedule.label,
                  else: "No description"}
              </p>
            </div>
          </div>
          <div class="flex items-center gap-2">
            <input
              type="checkbox"
              class="toggle toggle-primary toggle-sm"
              checked={@schedule.enabled}
              phx-click="toggle_schedule"
              phx-value-id={@schedule.id}
            />
            <button
              phx-click="edit_schedule"
              phx-value-id={@schedule.id}
              class="btn btn-ghost btn-sm btn-square"
            >
              <.icon name="hero-pencil-square" class="size-4" />
            </button>
            <button
              phx-click="delete_schedule"
              phx-value-id={@schedule.id}
              phx-confirm={"Delete \"#{@schedule.name}\"? This cannot be undone."}
              class="btn btn-ghost btn-sm btn-square text-error"
            >
              <.icon name="hero-trash" class="size-4" />
            </button>
          </div>
        </div>

        <%!-- Schedule info --%>
        <div class="mt-4 space-y-3">
          <div class="flex items-center gap-2">
            <.icon name="hero-clock" class="size-4 text-base-content/40" />
            <span class="text-sm font-medium">{@schedule.start_time}</span>
          </div>

          <div class="flex items-center gap-1.5">
            <%= for {name, idx} <- Enum.with_index(@day_names) do %>
              <span class={[
                "w-8 h-8 rounded-full flex items-center justify-center text-xs font-semibold",
                if(day_selected?(@schedule, idx),
                  do: "bg-primary text-primary-content",
                  else: "bg-base-200 text-base-content/30"
                )
              ]}>
                {String.first(name)}
              </span>
            <% end %>
          </div>
        </div>

        <%!-- Zone table --%>
        <div class="mt-4">
          <p class="text-xs font-semibold uppercase tracking-wide text-base-content/40 mb-2">Zones</p>
          <div class="space-y-2">
            <%= for zone <- @zones do %>
              <% sz = zone_in_schedule(@schedule, zone.id) %>
              <div class="flex items-center gap-3 py-1.5 border-b border-base-200 last:border-0">
                <input
                  type="checkbox"
                  class="checkbox checkbox-primary checkbox-sm"
                  checked={sz && sz.enabled}
                  phx-click="toggle_zone_in_schedule"
                  phx-value-schedule_id={@schedule.id}
                  phx-value-zone_id={zone.id}
                  phx-value-enabled={if sz && sz.enabled, do: "false", else: "true"}
                />
                <span class="flex-1 text-sm font-medium truncate">{zone.name}</span>
                <div class="flex items-center gap-1.5">
                  <input
                    type="number"
                    class="input input-bordered input-xs w-16 text-center"
                    value={if sz, do: div(sz.runtime_seconds, 60), else: 10}
                    min="1"
                    max="120"
                    phx-blur="update_zone_runtime"
                    phx-value-schedule_id={@schedule.id}
                    phx-value-zone_id={zone.id}
                    name="runtime"
                  />
                  <span class="text-xs text-base-content/40">min</span>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Edit form modal-like inline section --%>
        <%= if @editing do %>
          <div class="mt-4 p-4 bg-base-200 rounded-xl space-y-3">
            <h3 class="font-semibold text-sm">Edit Schedule Settings</h3>
            <.form for={@form} phx-submit="save_schedule">
              <div class="space-y-3">
                <div>
                  <label class="label label-text text-xs">Name</label>
                  <.input field={@form[:name]} class="input input-bordered input-sm w-full" />
                </div>
                <div>
                  <label class="label label-text text-xs">Description</label>
                  <.input field={@form[:label]} class="input input-bordered input-sm w-full" />
                </div>
                <div>
                  <label class="label label-text text-xs">Start Time</label>
                  <.input
                    type="time"
                    field={@form[:start_time]}
                    class="input input-bordered input-sm w-full"
                  />
                </div>
                <div>
                  <label class="label label-text text-xs">Days</label>
                  <div class="flex gap-1.5 flex-wrap">
                    <%= for {name, idx} <- Enum.with_index(@day_names) do %>
                      <label class="cursor-pointer">
                        <input
                          type="checkbox"
                          class="hidden peer"
                          name="schedule[days_of_week][]"
                          value={idx}
                          checked={day_selected?(@schedule, idx)}
                        />
                        <span class="w-9 h-9 rounded-full flex items-center justify-center text-xs font-semibold bg-base-300 text-base-content/40 peer-checked:bg-primary peer-checked:text-primary-content cursor-pointer select-none">
                          {String.slice(name, 0, 2)}
                        </span>
                      </label>
                    <% end %>
                  </div>
                </div>
                <div class="flex gap-2 mt-2">
                  <button type="submit" class="btn btn-primary btn-sm flex-1">Save</button>
                  <button type="button" phx-click="cancel_edit" class="btn btn-ghost btn-sm">
                    Cancel
                  </button>
                </div>
              </div>
            </.form>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
