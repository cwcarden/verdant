defmodule VerdantWeb.SettingsLive do
  use VerdantWeb, :live_view
  alias Verdant.Settings

  @setting_groups [
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
        %{key: "email_to", label: "To Address", type: "text", placeholder: "you@yourdomain.com"}
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
     |> assign(:saved_keys, MapSet.new())}
  end

  defp load_all_settings do
    all_keys =
      @setting_groups
      |> Enum.flat_map(& &1.fields)
      |> Enum.map(& &1.key)

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

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={@active_tab}>
      <div class="space-y-6">
        <div>
          <h1 class="text-2xl font-bold">Settings</h1>
          <p class="text-sm text-base-content/50 mt-0.5">Configure your irrigation system</p>
        </div>

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

                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <%= for field <- group.fields do %>
                      <div class="form-control">
                        <label class="label">
                          <span class="label-text text-sm font-medium">{field.label}</span>
                        </label>
                        <%= if field.type == "checkbox" do %>
                          <label class="flex items-center gap-3 cursor-pointer">
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
                        <% else %>
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
      </div>
    </Layouts.app>
    """
  end
end
