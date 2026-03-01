alias Verdant.Repo
alias Verdant.Zones.Zone
alias Verdant.Schedules.{Schedule, ScheduleZone}
alias Verdant.Settings.Setting
import Ecto.Query

# --- Default Zones (mirrored from original sprinkler config) ---
# GPIO pins: master valve = 2, zones 1-7 = 3-9 (BCM numbering)

zones = [
  %{name: "Back Yard Upper",       description: "Houseside back yard",          gpio_pin: 3,  position: 1, enabled: true,  water_heads: 0, flow_rate_gpm: 0.0},
  %{name: "Back Yard Lower",       description: "Fenceside back yard",           gpio_pin: 4,  position: 2, enabled: true,  water_heads: 0, flow_rate_gpm: 0.0},
  %{name: "Front Yard Doorside",   description: "Front yard door and mound",     gpio_pin: 5,  position: 3, enabled: true,  water_heads: 0, flow_rate_gpm: 0.0},
  %{name: "Front Yard Mound",      description: "Neighbor-side front yard",      gpio_pin: 6,  position: 4, enabled: true,  water_heads: 0, flow_rate_gpm: 0.0},
  %{name: "Front Yard Southside",  description: "South side front yard",         gpio_pin: 7,  position: 5, enabled: true,  water_heads: 0, flow_rate_gpm: 0.0},
  %{name: "Raised Garden",         description: "Garden beds",                   gpio_pin: 8,  position: 6, enabled: true,  water_heads: 0, flow_rate_gpm: 0.0},
  %{name: "Front-North & Grapes",  description: "North front yard and grapes",   gpio_pin: 9,  position: 7, enabled: true,  water_heads: 0, flow_rate_gpm: 0.0},
]

inserted_zones =
  Enum.map(zones, fn attrs ->
    existing = Repo.get_by(Zone, gpio_pin: attrs.gpio_pin)
    if existing do
      existing
    else
      Repo.insert!(%Zone{
        name: attrs.name,
        description: attrs.description,
        gpio_pin: attrs.gpio_pin,
        position: attrs.position,
        enabled: attrs.enabled,
        water_heads: attrs.water_heads,
        flow_rate_gpm: attrs.flow_rate_gpm
      })
    end
  end)

IO.puts("Seeded #{length(inserted_zones)} zones")

# --- Default Schedules ---
# Schedule A: Mon/Wed/Fri — zones 1, 2, 6 (indexes 0, 1, 5)
# Schedule B: Tue/Thu/Sat — zones 1, 2, 4, 5, 6 (indexes 0, 1, 3, 4, 5)

schedule_a_attrs = %{
  name: "Schedule A",
  label: "Mon / Wed / Fri",
  enabled: false,
  days_of_week: "1,3,5",
  start_time: "06:00",
  master_valve_warmup_seconds: 2
}

schedule_b_attrs = %{
  name: "Schedule B",
  label: "Tue / Thu / Sat",
  enabled: false,
  days_of_week: "2,4,6",
  start_time: "06:00",
  master_valve_warmup_seconds: 2
}

schedule_a =
  case Repo.get_by(Schedule, name: "Schedule A") do
    nil -> Repo.insert!(struct(Schedule, schedule_a_attrs))
    existing -> existing
  end

schedule_b =
  case Repo.get_by(Schedule, name: "Schedule B") do
    nil -> Repo.insert!(struct(Schedule, schedule_b_attrs))
    existing -> existing
  end

IO.puts("Seeded schedules A and B")

# --- Schedule Zone assignments ---
# Schedule A: zones 1 & 2 = 1600s (~27min), zone 6 = 400s (~7min)
schedule_a_zones = [
  {0, 1600}, # Back Yard Upper
  {1, 1600}, # Back Yard Lower
  {5, 400},  # Raised Garden
]

# Schedule B: zones 1 & 2 = 1600s, zones 4 & 5 = 900s, zone 6 = 400s
schedule_b_zones = [
  {0, 1600}, # Back Yard Upper
  {1, 1600}, # Back Yard Lower
  {3, 900},  # Front Yard Mound
  {4, 900},  # Front Yard Southside
  {5, 400},  # Raised Garden
]

all_zone_ids = Enum.map(inserted_zones, & &1.id)

# Insert schedule zones for Schedule A
Enum.each(Enum.with_index(inserted_zones), fn {zone, idx} ->
  {_zone_idx, runtime} = Enum.find(schedule_a_zones, {idx, 600}, fn {i, _} -> i == idx end)
  enabled = Enum.any?(schedule_a_zones, fn {i, _} -> i == idx end)

  existing = Repo.get_by(ScheduleZone, schedule_id: schedule_a.id, zone_id: zone.id)
  unless existing do
    Repo.insert!(%ScheduleZone{
      schedule_id: schedule_a.id,
      zone_id: zone.id,
      enabled: enabled,
      runtime_seconds: runtime
    })
  end
end)

# Insert schedule zones for Schedule B
Enum.each(Enum.with_index(inserted_zones), fn {zone, idx} ->
  {_zone_idx, runtime} = Enum.find(schedule_b_zones, {idx, 600}, fn {i, _} -> i == idx end)
  enabled = Enum.any?(schedule_b_zones, fn {i, _} -> i == idx end)

  existing = Repo.get_by(ScheduleZone, schedule_id: schedule_b.id, zone_id: zone.id)
  unless existing do
    Repo.insert!(%ScheduleZone{
      schedule_id: schedule_b.id,
      zone_id: zone.id,
      enabled: enabled,
      runtime_seconds: runtime
    })
  end
end)

IO.puts("Seeded schedule zone configurations")

# --- Default Settings ---
defaults = [
  {"ambient_api_key",                  "",     "Ambient Weather API key"},
  {"ambient_app_key",                  "",     "Ambient Weather application key"},
  {"ambient_mac",                      "",     "Weather station MAC address"},
  {"weather_fetch_interval_minutes",   "15",   "How often to fetch weather data (minutes)"},
  {"skip_rain_hours",                  "24",   "Skip watering if rain within this many hours"},
  {"skip_rain_inches",                 "0.25", "Skip watering if daily rain exceeds this (inches)"},
  {"skip_wind_mph",                    "25",   "Skip watering if wind exceeds this speed (mph)"},
  {"skip_temp_min",                    "32",   "Skip watering if temperature is below this (°F)"},
  {"skip_temp_max",                    "110",  "Skip watering if temperature is above this (°F)"},
  {"smtp_host",                        "",     "SMTP server hostname"},
  {"smtp_port",                        "587",  "SMTP server port"},
  {"smtp_user",                        "",     "SMTP username"},
  {"smtp_password",                    "",     "SMTP password"},
  {"email_from",                       "",     "From email address for notifications"},
  {"email_to",                         "",     "To email address for notifications"},
  {"notifications_enabled",            "false","Enable email notifications"},
  {"master_valve_pin",                 "2",    "Master valve GPIO pin (BCM)"},
]

Enum.each(defaults, fn {key, value, description} ->
  existing = Repo.get_by(Setting, key: key)
  unless existing do
    Repo.insert!(%Setting{key: key, value: value, description: description})
  end
end)

IO.puts("Seeded #{length(defaults)} default settings")
IO.puts("\nSeed complete! Run `mix phx.server` to start Verdant.")
