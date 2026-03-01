defmodule Verdant.Weather.WeatherReading do
  use Ecto.Schema
  import Ecto.Changeset

  schema "weather_readings" do
    field :recorded_at, :utc_datetime
    field :station_name, :string
    field :temperature_f, :float
    field :feels_like_f, :float
    field :humidity_pct, :float
    field :wind_speed_mph, :float
    field :wind_gust_mph, :float
    field :wind_direction_deg, :integer
    field :rain_hourly_in, :float
    field :rain_daily_in, :float
    field :rain_weekly_in, :float
    field :rain_monthly_in, :float
    field :rain_event_in, :float
    field :rain_total_in, :float
    field :pressure_inhg, :float
    field :pressure_trend, :string
    field :uv_index, :integer
    field :solar_radiation_wm2, :float
    field :dew_point_f, :float

    timestamps(type: :utc_datetime)
  end

  def changeset(reading, attrs) do
    reading
    |> cast(attrs, [:recorded_at, :station_name, :temperature_f, :feels_like_f,
                    :humidity_pct, :wind_speed_mph, :wind_gust_mph, :wind_direction_deg,
                    :rain_hourly_in, :rain_daily_in, :rain_weekly_in, :rain_monthly_in,
                    :rain_event_in, :rain_total_in, :pressure_inhg, :pressure_trend,
                    :uv_index, :solar_radiation_wm2, :dew_point_f])
    |> validate_required([:recorded_at])
  end
end
