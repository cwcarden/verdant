defmodule Verdant.Schedules do
  import Ecto.Query
  alias Verdant.Repo
  alias Verdant.Schedules.{Schedule, ScheduleZone}

  def list_schedules do
    Schedule
    |> order_by(:name)
    |> preload(schedule_zones: :zone)
    |> Repo.all()
  end

  def get_schedule!(id) do
    Schedule
    |> preload(schedule_zones: :zone)
    |> Repo.get!(id)
  end

  def get_schedule_by_name(name) do
    Schedule
    |> preload(schedule_zones: :zone)
    |> Repo.get_by(name: name)
  end

  def create_schedule(attrs) do
    %Schedule{}
    |> Schedule.changeset(attrs)
    |> Repo.insert()
  end

  def update_schedule(%Schedule{} = schedule, attrs) do
    schedule
    |> Schedule.changeset(attrs)
    |> Repo.update()
  end

  def upsert_schedule_zone(attrs) do
    %ScheduleZone{}
    |> ScheduleZone.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:enabled, :runtime_seconds, :updated_at]},
      conflict_target: [:schedule_id, :zone_id]
    )
  end

  def change_schedule(%Schedule{} = schedule, attrs \\ %{}),
    do: Schedule.changeset(schedule, attrs)
end
