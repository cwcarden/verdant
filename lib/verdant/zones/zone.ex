defmodule Verdant.Zones.Zone do
  use Ecto.Schema
  import Ecto.Changeset

  schema "zones" do
    field :name, :string
    field :description, :string, default: ""
    field :gpio_pin, :integer
    field :position, :integer
    field :enabled, :boolean, default: true
    field :water_heads, :integer, default: 0
    field :flow_rate_gpm, :float, default: 0.0

    has_many :schedule_zones, Verdant.Schedules.ScheduleZone
    has_many :schedules, through: [:schedule_zones, :schedule]
    has_many :watering_sessions, Verdant.Watering.WateringSession

    timestamps(type: :utc_datetime)
  end

  def changeset(zone, attrs) do
    zone
    |> cast(attrs, [
      :name,
      :description,
      :gpio_pin,
      :position,
      :enabled,
      :water_heads,
      :flow_rate_gpm
    ])
    |> validate_required([:name, :gpio_pin, :position])
    |> validate_number(:gpio_pin, greater_than: 0, less_than: 28)
    |> validate_number(:position, greater_than: 0, less_than: 9)
    |> validate_number(:water_heads, greater_than_or_equal_to: 0)
    |> validate_number(:flow_rate_gpm, greater_than_or_equal_to: 0.0)
    |> unique_constraint(:gpio_pin)
    |> unique_constraint(:position)
  end
end
