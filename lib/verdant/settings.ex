defmodule Verdant.Settings do
  import Ecto.Query
  alias Verdant.Repo
  alias Verdant.Settings.Setting

  @defaults %{
    "ambient_api_key" => "",
    "ambient_app_key" => "",
    "ambient_mac" => "",
    "weather_fetch_interval_minutes" => "15",
    "skip_rain_hours" => "24",
    "skip_rain_inches" => "0.25",
    "skip_wind_mph" => "25",
    "skip_temp_min" => "32",
    "skip_temp_max" => "110",
    "smtp_host" => "",
    "smtp_port" => "587",
    "smtp_user" => "",
    "smtp_password" => "",
    "email_from" => "",
    "email_to" => "",
    "notifications_enabled" => "false",
    "notify_schedule_start" => "false",
    "notify_schedule_complete" => "true",
    "notify_schedule_skipped" => "true",
    "notify_manual_start" => "false",
    "notify_manual_stop" => "false",
    "master_valve_pin" => "2",
    "timezone" => "America/Chicago",
    "history_display_limit" => "100",
    "history_retain_sessions" => "500",
    "weather_retain_readings" => "2880",
    "pin_lock_enabled" => "false",
    "pin_code" => "",
    "auto_lock_minutes" => "30"
  }

  def get(key, default \\ nil) do
    case Repo.get_by(Setting, key: key) do
      %Setting{value: value} -> value
      nil -> Map.get(@defaults, key, default)
    end
  end

  def get_float(key, default \\ 0.0) do
    case get(key) do
      nil -> default
      "" -> default
      val -> Float.parse(val) |> elem(0)
    end
  rescue
    _ -> default
  end

  def get_integer(key, default \\ 0) do
    case get(key) do
      nil -> default
      "" -> default
      val -> String.to_integer(val)
    end
  rescue
    _ -> default
  end

  def get_bool(key, default \\ false) do
    case get(key) do
      "true" -> true
      "false" -> false
      nil -> default
    end
  end

  def set(key, value) do
    case Repo.get_by(Setting, key: key) do
      nil ->
        %Setting{}
        |> Setting.changeset(%{key: key, value: to_string(value)})
        |> Repo.insert()

      setting ->
        setting
        |> Setting.changeset(%{value: to_string(value)})
        |> Repo.update()
    end
  end

  def all do
    Setting |> order_by(:key) |> Repo.all()
  end

  def defaults, do: @defaults
end
