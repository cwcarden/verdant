defmodule Verdant.Schedules.ScheduleZone do
  use Ecto.Schema
  import Ecto.Changeset

  schema "schedule_zones" do
    field :enabled, :boolean, default: true
    field :runtime_seconds, :integer, default: 600

    belongs_to :schedule, Verdant.Schedules.Schedule
    belongs_to :zone, Verdant.Zones.Zone

    timestamps(type: :utc_datetime)
  end

  def changeset(schedule_zone, attrs) do
    schedule_zone
    |> cast(attrs, [:schedule_id, :zone_id, :enabled, :runtime_seconds])
    |> validate_required([:schedule_id, :zone_id, :runtime_seconds])
    |> validate_number(:runtime_seconds, greater_than: 0)
    |> unique_constraint([:schedule_id, :zone_id])
  end
end
