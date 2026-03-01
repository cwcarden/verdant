defmodule Verdant.Watering.WateringSession do
  use Ecto.Schema
  import Ecto.Changeset

  schema "watering_sessions" do
    field :zone_name, :string
    field :trigger, :string, default: "manual"
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :planned_duration_seconds, :integer
    field :actual_duration_seconds, :integer
    field :skipped, :boolean, default: false
    field :skip_reason, :string

    belongs_to :zone, Verdant.Zones.Zone
    belongs_to :schedule, Verdant.Schedules.Schedule

    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :zone_id,
      :schedule_id,
      :zone_name,
      :trigger,
      :started_at,
      :ended_at,
      :planned_duration_seconds,
      :actual_duration_seconds,
      :skipped,
      :skip_reason
    ])
    |> validate_required([:zone_name, :started_at])
  end
end
