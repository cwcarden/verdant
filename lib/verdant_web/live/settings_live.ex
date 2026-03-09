defmodule VerdantWeb.SettingsLive do
  use VerdantWeb, :live_view
  alias Verdant.{Settings, LocalTime}

  @setting_groups [
    %{
      id: :system,
      title: "System",
      icon: "hero-cog-6-tooth",
      description: "General system configuration",
      fields: [
        %{
          key: "timezone",
          label: "Timezone",
          type: "select",
          placeholder: "",
          options: :us_timezones
        }
      ]
    },
    %{
      id: :weather_api,
      title: "Ambient Weather API",
      icon: "hero-cloud",
      description: "WS-2000 weather station connection",
      fields: [
        %{
          key: "ambient_api_key",
          label: "API Key",
          type: "password",
          placeholder: "Your Ambient Weather API key"
        },
        %{
          key: "ambient_app_key",
          label: "Application Key",
          type: "password",
          placeholder: "Your application key"
        },
        %{
          key: "ambient_mac",
          label: "Station MAC Address",
          type: "text",
          placeholder: "AA:BB:CC:DD:EE:FF"
        },
        %{
          key: "weather_fetch_interval_minutes",
          label: "Fetch Interval (minutes)",
          type: "number",
          placeholder: "15"
        }
      ]
    },
    %{
      id: :skip_conditions,
      title: "Watering Skip Conditions",
      icon: "hero-shield-check",
      description: "Automatically skip watering when these weather thresholds are met",
      fields: [
        %{
          key: "skip_rain_hours",
          label: "Skip if rain within (hours)",
          type: "number",
          placeholder: "24"
        },
        %{
          key: "skip_rain_inches",
          label: "Skip if daily rain exceeds (inches)",
          type: "number",
          placeholder: "0.25"
        },
        %{
          key: "skip_wind_mph",
          label: "Skip if wind exceeds (mph)",
          type: "number",
          placeholder: "25"
        },
        %{
          key: "skip_temp_min",
          label: "Skip if temperature below (°F)",
          type: "number",
          placeholder: "32"
        },
        %{
          key: "skip_temp_max",
          label: "Skip if temperature above (°F)",
          type: "number",
          placeholder: "110"
        }
      ]
    },
    %{
      id: :notifications,
      title: "Email Notifications",
      icon: "hero-envelope",
      description: "SMTP settings for watering event notifications",
      fields: [
        %{
          key: "notifications_enabled",
          label: "Enable Notifications",
          type: "checkbox",
          placeholder: ""
        },
        %{key: "smtp_host", label: "SMTP Host", type: "text", placeholder: "smtp.gmail.com"},
        %{key: "smtp_port", label: "SMTP Port", type: "number", placeholder: "587"},
        %{key: "smtp_user", label: "SMTP Username", type: "text", placeholder: "your@email.com"},
        %{
          key: "smtp_password",
          label: "SMTP Password",
          type: "password",
          placeholder: "App password"
        },
        %{
          key: "email_from",
          label: "From Address",
          type: "text",
          placeholder: "verdant@yourdomain.com"
        },
        %{key: "email_to", label: "To Address", type: "text", placeholder: "you@yourdomain.com"},
        %{
          key: "notify_schedule_start",
          label: "Notify when a schedule starts",
          type: "checkbox",
          placeholder: ""
        },
        %{
          key: "notify_schedule_complete",
          label: "Notify when a schedule completes",
          type: "checkbox",
          placeholder: ""
        },
        %{
          key: "notify_schedule_skipped",
          label: "Notify when a schedule is skipped (weather)",
          type: "checkbox",
          placeholder: ""
        },
        %{
          key: "notify_manual_start",
          label: "Notify when manual watering starts",
          type: "checkbox",
          placeholder: ""
        },
        %{
          key: "notify_manual_stop",
          label: "Notify when manual watering is stopped",
          type: "checkbox",
          placeholder: ""
        }
      ]
    },
    %{
      id: :data_retention,
      title: "Data Retention",
      icon: "hero-archive-box",
      description: "Control how much history is stored and displayed",
      fields: [
        %{
          key: "history_display_limit",
          label: "Watering history rows to display",
          type: "number",
          placeholder: "100"
        },
        %{
          key: "history_retain_sessions",
          label: "Watering sessions to keep in database",
          type: "number",
          placeholder: "500"
        },
        %{
          key: "weather_retain_readings",
          label: "Weather readings to keep in database",
          type: "number",
          placeholder: "2880"
        }
      ]
    },
    %{
      id: :hardware,
      title: "Hardware",
      icon: "hero-cpu-chip",
      description: "Raspberry Pi GPIO configuration",
      fields: [
        %{
          key: "master_valve_pin",
          label: "Master Valve GPIO Pin (BCM)",
          type: "number",
          placeholder: "2"
        }
      ]
    },
    %{
      id: :security,
      title: "Security",
      icon: "hero-lock-closed",
      description: "PIN passcode lock to prevent unauthorized access",
      fields: [
        %{
          key: "pin_lock_enabled",
          label: "Enable PIN Lock",
          type: "checkbox",
          placeholder: ""
        },
        %{
          key: "auto_lock_minutes",
          label: "Auto-lock after (minutes, 0 = never)",
          type: "number",
          placeholder: "30"
        }
      ]
    }
  ]

  def mount(_params, _session, socket) do
    settings = load_all_settings()

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:active_tab, :settings)
     |> assign(:settings, settings)
     |> assign(:setting_groups, @setting_groups)
     |> assign(:saved_keys, MapSet.new())
     |> assign(:show_password_fields, MapSet.new())}
  end

  defp load_all_settings do
    all_keys =
      @setting_groups
      |> Enum.flat_map(& &1.fields)
      |> Enum.map(& &1.key)

    # Also always include pin_code so the security section can show PIN status
    all_keys = ["pin_code" | all_keys]

    Map.new(all_keys, fn key -> {key, Settings.get(key, "")} end)
  end

  def handle_event("save_settings", %{"settings" => params}, socket) do
    saved_keys =
      Enum.reduce(params, MapSet.new(), fn {key, value}, acc ->
        Settings.set(key, value)
        MapSet.put(acc, key)
      end)

    {:noreply,
     socket
     |> put_flash(:info, "Settings saved")
     |> assign(:settings, load_all_settings())
     |> assign(:saved_keys, saved_keys)}
  end

  def handle_event("toggle_password_field", %{"key" => key}, socket) do
    updated =
      if MapSet.member?(socket.assigns.show_password_fields, key) do
        MapSet.delete(socket.assigns.show_password_fields, key)
      else
        MapSet.put(socket.assigns.show_password_fields, key)
      end

    {:noreply, assign(socket, :show_password_fields, updated)}
  end

  def handle_event("test_email", _params, socket) do
    case Verdant.Notifier.test_email() do
      {:ok, :sent} ->
        {:noreply, put_flash(socket, :info, "Test email sent! Check your inbox.")}

      {:error, :not_configured} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Email not fully configured — please fill in all SMTP fields and save first."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to send test email: #{inspect(reason)}")}
    end
  end

  def handle_event("change_pin", %{"pin" => %{"new" => new_pin, "confirm" => confirm}}, socket) do
    cond do
      String.length(new_pin) < 4 or String.length(new_pin) > 6 ->
        {:noreply, put_flash(socket, :error, "Passcode must be 4–6 digits")}

      not String.match?(new_pin, ~r/^\d+$/) ->
        {:noreply, put_flash(socket, :error, "Passcode must contain only numbers")}

      new_pin != confirm ->
        {:noreply, put_flash(socket, :error, "Passcodes do not match")}

      true ->
        Settings.set("pin_code", new_pin)

        {:noreply,
         socket
         |> put_flash(:info, "Passcode updated")
         |> assign(:settings, load_all_settings())}
    end
  end

  def handle_event("remove_pin", _params, socket) do
    Settings.set("pin_code", "")

    {:noreply,
     socket
     |> put_flash(:info, "Passcode removed")
     |> assign(:settings, load_all_settings())}
  end

  def handle_event("lock_now", _params, socket) do
    {:noreply, push_navigate(socket, to: "/session/lock")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={@active_tab}>
      <div class="space-y-6">
        <div>
          <h1 class="text-2xl font-bold">Settings</h1>
          <p class="text-sm text-base-content/50 mt-0.5">Configure your irrigation system</p>
        </div>

        <%!-- Main settings form — all groups including Security toggles --%>
        <.form for={%{}} as={:settings} phx-submit="save_settings">
          <div class="space-y-6">
            <%= for group <- @setting_groups do %>
              <div class="card bg-base-100 shadow-sm">
                <div class="card-body p-5">
                  <div class="flex items-center gap-3 mb-4">
                    <div class="size-10 bg-primary/10 rounded-xl flex items-center justify-center">
                      <.icon name={group.icon} class="size-5 text-primary" />
                    </div>
                    <div>
                      <h2 class="font-bold">{group.title}</h2>
                      <p class="text-xs text-base-content/50">{group.description}</p>
                    </div>
                  </div>

                  <%= if group.id == :notifications do %>
                    <div class="flex justify-end mb-3">
                      <button
                        type="button"
                        phx-click="test_email"
                        class="btn btn-secondary btn-sm gap-2"
                      >
                        <.icon name="hero-paper-airplane" class="size-4" />
                        Send Test Email
                      </button>
                    </div>
                  <% end %>

                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <%= for field <- group.fields do %>
                      <div class="form-control">
                        <label class="label">
                          <span class="label-text text-sm font-medium">{field.label}</span>
                        </label>
                        <%= cond do %>
                          <% field.type == "select" -> %>
                            <select
                              name={"settings[#{field.key}]"}
                              class="select select-bordered select-sm w-full"
                            >
                              <%= for {opt_label, opt_value} <- LocalTime.us_timezones() do %>
                                <option
                                  value={opt_value}
                                  selected={Map.get(@settings, field.key) == opt_value}
                                >
                                  {opt_label}
                                </option>
                              <% end %>
                            </select>
                          <% field.type == "checkbox" -> %>
                            <label class="flex items-center gap-3 cursor-pointer">
                              <%!-- Hidden input ensures "false" is submitted when the checkbox is unchecked --%>
                              <input type="hidden" name={"settings[#{field.key}]"} value="false" />
                              <input
                                type="checkbox"
                                name={"settings[#{field.key}]"}
                                class="toggle toggle-primary"
                                value="true"
                                checked={Map.get(@settings, field.key) == "true"}
                              />
                              <span class="text-sm text-base-content/60">
                                {if Map.get(@settings, field.key) == "true",
                                  do: "Enabled",
                                  else: "Disabled"}
                              </span>
                            </label>
                          <% field.type == "password" -> %>
                            <div class="relative">
                              <input
                                type={if MapSet.member?(@show_password_fields, field.key), do: "text", else: "password"}
                                name={"settings[#{field.key}]"}
                                class="input input-bordered input-sm w-full pr-10"
                                placeholder={field.placeholder}
                                value={Map.get(@settings, field.key, "")}
                              />
                              <button
                                type="button"
                                class="absolute inset-y-0 right-0 flex items-center pr-3 text-base-content/40 hover:text-base-content/70"
                                phx-click="toggle_password_field"
                                phx-value-key={field.key}
                              >
                                <%= if MapSet.member?(@show_password_fields, field.key) do %>
                                  <.icon name="hero-eye-slash-micro" class="size-4" />
                                <% else %>
                                  <.icon name="hero-eye-micro" class="size-4" />
                                <% end %>
                              </button>
                            </div>
                          <% true -> %>
                            <input
                              type={field.type}
                              name={"settings[#{field.key}]"}
                              class="input input-bordered input-sm w-full"
                              placeholder={field.placeholder}
                              value={Map.get(@settings, field.key, "")}
                            />
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>

            <div class="flex justify-end gap-3">
              <button type="submit" class="btn btn-primary">
                <.icon name="hero-check" class="size-4" /> Save All Settings
              </button>
            </div>
          </div>
        </.form>

        <%!--
          PIN Management — intentionally a SEPARATE form outside the settings form above.
          Nested <form> elements are invalid HTML and browsers ignore the inner form,
          so this must live at the top level.
        --%>
        <.form for={%{}} as={:pin} phx-submit="change_pin">
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-5">
              <div class="flex items-center gap-3 mb-4">
                <div class="size-10 bg-primary/10 rounded-xl flex items-center justify-center">
                  <.icon name="hero-key" class="size-5 text-primary" />
                </div>
                <div>
                  <h2 class="font-bold">Passcode Management</h2>
                  <p class="text-xs text-base-content/50">Set or change the lock screen passcode</p>
                </div>
              </div>

              <%!-- Current PIN status row --%>
              <div class="flex items-center justify-between mb-4 p-3 bg-base-200 rounded-xl">
                <div>
                  <p class="text-sm font-medium">Current Passcode</p>
                  <%= if Map.get(@settings, "pin_code", "") != "" do %>
                    <p class="text-xs text-success mt-0.5">
                      <.icon name="hero-lock-closed-micro" class="size-3 inline" />
                      {"●" |> String.duplicate(String.length(Map.get(@settings, "pin_code", "")))}
                      &nbsp;({String.length(Map.get(@settings, "pin_code", ""))} digits set)
                    </p>
                  <% else %>
                    <p class="text-xs text-base-content/50 mt-0.5">
                      <.icon name="hero-lock-open-micro" class="size-3 inline" /> Not set
                    </p>
                  <% end %>
                </div>
                <div class="flex gap-2">
                  <%= if Map.get(@settings, "pin_code", "") != "" do %>
                    <button
                      type="button"
                      phx-click="remove_pin"
                      class="btn btn-ghost btn-sm text-error gap-1"
                    >
                      <.icon name="hero-trash-micro" class="size-3" /> Remove
                    </button>
                  <% end %>
                  <%= if Map.get(@settings, "pin_lock_enabled") == "true" do %>
                    <button
                      type="button"
                      phx-click="lock_now"
                      class="btn btn-secondary btn-sm gap-1"
                    >
                      <.icon name="hero-lock-closed-micro" class="size-3" /> Lock Now
                    </button>
                  <% end %>
                </div>
              </div>

              <%!-- New / change passcode inputs --%>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-sm font-medium">
                      {if Map.get(@settings, "pin_code", "") != "",
                        do: "New Passcode",
                        else: "Set Passcode"}
                    </span>
                  </label>
                  <input
                    type="text"
                    name="pin[new]"
                    inputmode="numeric"
                    maxlength="6"
                    pattern="\d{4,6}"
                    autocomplete="off"
                    placeholder="4–6 digits"
                    class="input input-bordered input-sm w-full tracking-widest font-mono"
                  />
                </div>
                <div class="form-control">
                  <label class="label">
                    <span class="label-text text-sm font-medium">Confirm Passcode</span>
                  </label>
                  <input
                    type="text"
                    name="pin[confirm]"
                    inputmode="numeric"
                    maxlength="6"
                    pattern="\d{4,6}"
                    autocomplete="off"
                    placeholder="Repeat digits"
                    class="input input-bordered input-sm w-full tracking-widest font-mono"
                  />
                </div>
              </div>

              <div class="flex justify-end mt-4">
                <button type="submit" class="btn btn-primary btn-sm gap-2">
                  <.icon name="hero-check" class="size-4" />
                  {if Map.get(@settings, "pin_code", "") != "",
                    do: "Change Passcode",
                    else: "Save Passcode"}
                </button>
              </div>
            </div>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
