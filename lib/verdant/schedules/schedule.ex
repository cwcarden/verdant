defmodule Verdant.Schedules.Schedule do
  use Ecto.Schema
  import Ecto.Changeset

  schema "schedules" do
    field :name, :string
    field :label, :string, default: ""
    field :enabled, :boolean, default: false
    field :days_of_week, :string, default: ""
    field :start_time, :string, default: "06:00"
    field :master_valve_warmup_seconds, :integer, default: 2

    has_many :schedule_zones, Verdant.Schedules.ScheduleZone
    has_many :zones, through: [:schedule_zones, :zone]

    timestamps(type: :utc_datetime)
  end

  def changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [
      :name,
      :label,
      :enabled,
      :days_of_week,
      :start_time,
      :master_valve_warmup_seconds
    ])
    |> validate_required([:name])
    |> unique_constraint(:name)
    |> validate_format(:start_time, ~r/^\d{2}:\d{2}$/, message: "must be HH:MM format")
  end

  def days_list(%__MODULE__{days_of_week: days}) when is_binary(days) do
    days
    |> String.split(",", trim: true)
    |> Enum.map(&String.to_integer/1)
  end

  def days_list(_), do: []

  def day_names do
    ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  end
end
