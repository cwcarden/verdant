defmodule Verdant.Repo.Migrations.CreateWeatherReadings do
  use Ecto.Migration

  def change do
    create table(:weather_readings) do
      add :recorded_at, :utc_datetime, null: false
      add :station_name, :string
      add :temperature_f, :float
      add :feels_like_f, :float
      add :humidity_pct, :float
      add :wind_speed_mph, :float
      add :wind_gust_mph, :float
      add :wind_direction_deg, :integer
      add :rain_hourly_in, :float
      add :rain_daily_in, :float
      add :rain_weekly_in, :float
      add :rain_monthly_in, :float
      add :rain_event_in, :float
      add :rain_total_in, :float
      add :pressure_inhg, :float
      add :pressure_trend, :string
      add :uv_index, :integer
      add :solar_radiation_wm2, :float
      add :dew_point_f, :float

      timestamps(type: :utc_datetime)
    end

    create index(:weather_readings, [:recorded_at])
  end
end
