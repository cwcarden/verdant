defmodule Verdant.Schedules do
  import Ecto.Query
  alias Verdant.Repo
  alias Verdant.Schedules.{Schedule, ScheduleZone}
  alias Verdant.LocalTime

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

  def delete_schedule(%Schedule{} = schedule) do
    Repo.delete(schedule)
  end

  @doc """
  Returns a list of `{schedule_name, date, start_time_hhmm}` tuples — one per
  enabled schedule — sorted by (date, time) ascending.  Looks up to 7 days
  ahead from now (local time).  Schedules with no days configured are skipped.
  """
  def upcoming_runs do
    now = LocalTime.now()
    today = DateTime.to_date(now)
    current_hhmm = Calendar.strftime(now, "%H:%M")

    list_schedules()
    |> Enum.filter(& &1.enabled)
    |> Enum.filter(fn s -> Enum.any?(s.schedule_zones, & &1.enabled) end)
    |> Enum.flat_map(fn schedule ->
      days = Schedule.days_list(schedule)

      # Skip schedules that have no days configured at all
      if days == [] do
        []
      else
        result =
          Enum.find_value(0..6, fn offset ->
            check_date = Date.add(today, offset)
            check_dow = Date.day_of_week(check_date, :sunday) - 1

            cond do
              check_dow not in days -> nil
              # Today but the time has already passed (strictly past the current minute)
              offset == 0 && schedule.start_time <= current_hhmm -> nil
              true -> {schedule.name, check_date, schedule.start_time}
            end
          end)

        if result, do: [result], else: []
      end
    end)
    |> Enum.sort_by(fn {_name, date, time} -> {date, time} end)
  end
end
