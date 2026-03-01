defmodule Verdant.Weather do
  import Ecto.Query
  alias Verdant.Repo
  alias Verdant.Weather.WeatherReading
  alias Verdant.Settings

  def latest_reading do
    WeatherReading
    |> order_by(desc: :recorded_at)
    |> limit(1)
    |> Repo.one()
  end

  def recent_readings(hours \\ 24) do
    since = DateTime.utc_now() |> DateTime.add(-hours * 3600) |> DateTime.truncate(:second)
    WeatherReading
    |> where([r], r.recorded_at >= ^since)
    |> order_by(desc: :recorded_at)
    |> Repo.all()
  end

  def store_reading(attrs) do
    %WeatherReading{}
    |> WeatherReading.changeset(attrs)
    |> Repo.insert()
  end

  def fetch_from_api do
    api_key = Settings.get("ambient_api_key")
    app_key = Settings.get("ambient_app_key")
    mac = Settings.get("ambient_mac")

    if api_key && app_key && mac do
      url = "https://rt.ambientweather.net/v1/devices/#{mac}?apiKey=#{api_key}&applicationKey=#{app_key}&limit=1"
      case Req.get(url) do
        {:ok, %{status: 200, body: [data | _]}} ->
          parse_and_store(data)
        {:ok, %{status: status}} ->
          {:error, "API returned status #{status}"}
        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, "Ambient Weather API not configured"}
    end
  end

  defp parse_and_store(data) do
    recorded_at =
      case Map.get(data, "dateutc") do
        ms when is_integer(ms) ->
          DateTime.from_unix!(ms, :millisecond) |> DateTime.truncate(:second)
        _ ->
          DateTime.utc_now() |> DateTime.truncate(:second)
      end

    attrs = %{
      recorded_at: recorded_at,
      station_name: Map.get(data, "stationtype", "WS-2000"),
      temperature_f: Map.get(data, "tempf"),
      feels_like_f: Map.get(data, "feelsLike"),
      humidity_pct: Map.get(data, "humidity"),
      wind_speed_mph: Map.get(data, "windspeedmph"),
      wind_gust_mph: Map.get(data, "windgustmph"),
      wind_direction_deg: Map.get(data, "winddir"),
      rain_hourly_in: Map.get(data, "hourlyrainin"),
      rain_daily_in: Map.get(data, "dailyrainin"),
      rain_weekly_in: Map.get(data, "weeklyrainin"),
      rain_monthly_in: Map.get(data, "monthlyrainin"),
      rain_event_in: Map.get(data, "eventrainin"),
      rain_total_in: Map.get(data, "totalrainin"),
      pressure_inhg: Map.get(data, "baromrelin"),
      uv_index: Map.get(data, "uv"),
      solar_radiation_wm2: Map.get(data, "solarradiation"),
      dew_point_f: Map.get(data, "dewPoint")
    }

    store_reading(attrs)
  end

  def should_skip_watering? do
    reading = latest_reading()
    if reading do
      skip_rules = [
        check_rain_hours(reading),
        check_rain_inches(reading),
        check_wind_speed(reading),
        check_temperature(reading)
      ]
      Enum.find(skip_rules, fn {skip, _reason} -> skip end)
    else
      {false, nil}
    end
  end

  defp check_rain_hours(reading) do
    threshold = Settings.get_float("skip_rain_hours", 24.0)
    if reading.rain_daily_in && reading.rain_daily_in > 0 do
      hours_ago = DateTime.diff(DateTime.utc_now(), reading.recorded_at) / 3600
      {hours_ago < threshold, "Rain detected within #{threshold} hours"}
    else
      {false, nil}
    end
  end

  defp check_rain_inches(reading) do
    threshold = Settings.get_float("skip_rain_inches", 0.25)
    if reading.rain_daily_in && reading.rain_daily_in >= threshold do
      {true, "Daily rain #{reading.rain_daily_in}\" >= #{threshold}\""}
    else
      {false, nil}
    end
  end

  defp check_wind_speed(reading) do
    threshold = Settings.get_float("skip_wind_mph", 25.0)
    if reading.wind_speed_mph && reading.wind_speed_mph >= threshold do
      {true, "Wind #{reading.wind_speed_mph} mph >= #{threshold} mph"}
    else
      {false, nil}
    end
  end

  defp check_temperature(reading) do
    min_temp = Settings.get_float("skip_temp_min", 32.0)
    max_temp = Settings.get_float("skip_temp_max", 110.0)
    cond do
      reading.temperature_f && reading.temperature_f < min_temp ->
        {true, "Temperature #{reading.temperature_f}°F below minimum #{min_temp}°F"}
      reading.temperature_f && reading.temperature_f > max_temp ->
        {true, "Temperature #{reading.temperature_f}°F above maximum #{max_temp}°F"}
      true ->
        {false, nil}
    end
  end
end
