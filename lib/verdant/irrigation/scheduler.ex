defmodule Verdant.Irrigation.Scheduler do
  @moduledoc """
  GenServer that checks enabled schedules every minute and fires them when due.

  Uses the Pi's local time so start_time values in settings are local-time aware.
  Tracks which schedules ran today to prevent duplicate runs.
  Also checks weather skip conditions before starting.
  """

  use GenServer
  require Logger

  alias Verdant.{Schedules, Weather, Watering, Settings, LocalTime}
  alias Verdant.Irrigation.Runner

  # check every 60 seconds
  @check_interval 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_check()
    # Prune old records on startup so the DB doesn't grow unbounded
    run_prune()
    today = LocalTime.today()
    {:ok, %{ran_today: MapSet.new(), current_date: today}}
  end

  @impl true
  def handle_info(:check_schedules, state) do
    schedule_check()
    state = maybe_reset_daily(state)
    state = check_and_run(state)
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_schedules, @check_interval)
  end

  defp maybe_reset_daily(state) do
    today = LocalTime.today()

    if today != state.current_date do
      Logger.info("[Scheduler] New day detected (#{today}), resetting schedule tracker and pruning old records")
      run_prune()
      %{state | ran_today: MapSet.new(), current_date: today}
    else
      state
    end
  end

  defp run_prune do
    sessions_keep = Settings.get_integer("history_retain_sessions", 500)
    readings_keep = Settings.get_integer("weather_retain_readings", 2880)
    Watering.prune_old_sessions(sessions_keep)
    Weather.prune_old_readings(readings_keep)
  end

  defp check_and_run(state) do
    now = LocalTime.now()
    today = DateTime.to_date(now)
    # 0=Sun, 6=Sat
    today_dow = Date.day_of_week(today, :sunday) - 1

    current_hhmm =
      "#{String.pad_leading(to_string(now.hour), 2, "0")}:#{String.pad_leading(to_string(now.minute), 2, "0")}"

    schedules = Schedules.list_schedules()

    Enum.reduce(schedules, state, fn schedule, acc ->
      key = {schedule.id, today}

      cond do
        not schedule.enabled ->
          acc

        MapSet.member?(acc.ran_today, key) ->
          acc

        not day_matches?(schedule, today_dow) ->
          acc

        not time_matches?(schedule, current_hhmm) ->
          acc

        true ->
          run_schedule(schedule, acc, key)
      end
    end)
  end

  defp day_matches?(schedule, dow) do
    schedule.days_of_week
    |> String.split(",", trim: true)
    |> Enum.member?(to_string(dow))
  end

  defp time_matches?(schedule, current_hhmm) do
    schedule.start_time == current_hhmm
  end

  defp run_schedule(schedule, state, key) do
    Logger.info("[Scheduler] Schedule '#{schedule.name}' is due, fetching current weather...")

    # Fetch fresh weather from the API so skip checks use real-time conditions.
    # If credentials aren't set or the network is unavailable, fall back silently
    # to the most recent reading already stored in the database.
    case Weather.fetch_from_api() do
      {:ok, _} -> Logger.info("[Scheduler] Weather data refreshed successfully")
      {:error, reason} -> Logger.info("[Scheduler] Could not refresh weather (#{inspect(reason)}), using cached reading")
    end

    {should_skip, reason} = Weather.should_skip_watering?()

    if should_skip do
      Logger.info("[Scheduler] Skipping '#{schedule.name}': #{reason}")
      Runner.broadcast({:schedule_skipped, %{schedule_name: schedule.name, reason: reason}})
      %{state | ran_today: MapSet.put(state.ran_today, key)}
    else
      # Build ordered list of enabled zones with their runtimes
      zones_with_times =
        schedule.schedule_zones
        |> Enum.filter(& &1.enabled)
        |> Enum.sort_by(fn sz -> sz.zone.position end)
        |> Enum.map(fn sz -> {sz.zone, sz.runtime_seconds} end)

      if zones_with_times == [] do
        Logger.warning("[Scheduler] Schedule '#{schedule.name}' has no enabled zones, skipping")
        Runner.broadcast({:schedule_skipped, %{schedule_name: schedule.name, reason: "no enabled zones"}})
        %{state | ran_today: MapSet.put(state.ran_today, key)}
      else
        Logger.info(
          "[Scheduler] Starting schedule '#{schedule.name}' with #{length(zones_with_times)} zones"
        )

        case Runner.start_schedule(schedule, zones_with_times) do
          :ok ->
            %{state | ran_today: MapSet.put(state.ran_today, key)}

          {:error, :busy} ->
            Logger.warning("[Scheduler] Runner busy, will retry next minute")
            state

          {:error, reason} ->
            Logger.error("[Scheduler] Failed to start schedule: #{inspect(reason)}")
            state
        end
      end
    end
  end
end
