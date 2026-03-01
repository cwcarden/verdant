defmodule Verdant.Irrigation.Runner do
  @moduledoc """
  GenServer that manages active irrigation cycles.

  Supports concurrent manual zone runs: multiple zones can be open at the same
  time when started manually. Schedule runs remain sequential (queue-based).

  Pin logic (active-LOW relays):
  - write(ref, 0) → valve OPEN  (relay energized)
  - write(ref, 1) → valve CLOSED (relay de-energized)

  Sequence for a zone run:
  1. Open master valve (GPIO 2 default) – once, shared across all running zones
  2. Wait warmup_seconds (keeps pressure stable) on first zone start
  3. Open zone valve
  4. After runtime_seconds: close zone valve
  5. When all zones done and queue empty → close master valve
  """

  use GenServer
  require Logger

  alias Verdant.{GPIO, Watering, Settings}
  alias Phoenix.PubSub

  @pubsub Verdant.PubSub
  @topic "irrigation"

  # ── Public API ────────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Start a single zone manually. Concurrent zones are allowed; returns :ok or {:error, reason}."
  def start_zone(zone, runtime_seconds) do
    GenServer.call(__MODULE__, {:start_zone, zone, runtime_seconds})
  end

  @doc "Stop a specific zone by zone_id. Returns :ok or {:error, :not_found}."
  def stop_zone(zone_id) do
    GenServer.call(__MODULE__, {:stop_zone, zone_id})
  end

  @doc """
  Start a schedule run. zones_with_times is a list of {%Zone{}, runtime_seconds}.
  Returns {:error, :busy} if any zone is currently active.
  """
  def start_schedule(schedule, zones_with_times) do
    GenServer.call(__MODULE__, {:start_schedule, schedule, zones_with_times})
  end

  @doc "Stop all watering immediately."
  def stop_all do
    GenServer.call(__MODULE__, :stop)
  end

  @doc "Return current runner status map."
  def status do
    GenServer.call(__MODULE__, :status)
  end

  def subscribe, do: PubSub.subscribe(@pubsub, @topic)
  def broadcast(msg), do: PubSub.broadcast(@pubsub, @topic, msg)

  # ── GenServer callbacks ───────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    # End any DB sessions left open from a previous run (e.g. app restart mid-water).
    Watering.end_orphaned_sessions()
    {:ok, initial_state()}
  end

  defp initial_state do
    %{
      master_ref: nil,
      # list of %{zone, session, zone_ref, timer_ref, planned_seconds, started_at}
      active_zones: [],
      # [{zone, runtime_seconds}] remaining in a schedule run
      queue: [],
      schedule_id: nil,
      schedule_name: nil,
      # ref for the pending {:begin_zone} send_after during master-valve warmup
      warmup_timer_ref: nil
    }
  end

  # ── handle_call ──────────────────────────────────────────────────────────────

  @impl true
  def handle_call({:start_zone, zone, runtime_seconds}, _from, state) do
    # Concurrent manual zones are allowed — no :busy check here.
    if state.master_ref do
      # Master already open; skip warmup and begin immediately.
      Process.send_after(self(), {:begin_zone, zone, runtime_seconds, "manual", nil, nil}, 0)
      {:reply, :ok, state}
    else
      case open_master_valve(state) do
        {:ok, master_ref} ->
          warmup = Settings.get_integer("master_valve_warmup_seconds", 2)

          warmup_ref =
            Process.send_after(
              self(),
              {:begin_zone, zone, runtime_seconds, "manual", nil, nil},
              warmup * 1000
            )

          {:reply, :ok, %{state | master_ref: master_ref, warmup_timer_ref: warmup_ref}}

        {:error, reason} ->
          Logger.error("[Runner] Failed to open master valve: #{inspect(reason)}")
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call({:stop_zone, zone_id}, _from, state) do
    case Enum.find(state.active_zones, &(&1.zone.id == zone_id)) do
      nil ->
        {:reply, {:error, :not_found}, state}

      active ->
        Process.cancel_timer(active.timer_ref)
        GPIO.write(active.zone_ref, 1)
        GPIO.close(active.zone_ref)
        actual = DateTime.diff(DateTime.utc_now(), active.started_at)
        Watering.end_session(active.session)

        broadcast(
          {:watering_stopped,
           %{zone_name: active.zone.name, zone_id: zone_id, actual_seconds: actual, reason: :manual}}
        )

        new_active_zones = Enum.reject(state.active_zones, &(&1.zone.id == zone_id))
        state = %{state | active_zones: new_active_zones}
        state = maybe_close_master(state)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:start_schedule, _schedule, []}, _from, state) do
    {:reply, {:error, :no_zones}, state}
  end

  # Schedules don't run concurrently with active zones.
  def handle_call({:start_schedule, _schedule, _zones}, _from, %{active_zones: [_ | _]} = state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call({:start_schedule, schedule, [{first_zone, first_runtime} | rest]}, _from, state) do
    case open_master_valve(state) do
      {:ok, master_ref} ->
        warmup = Settings.get_integer("master_valve_warmup_seconds", 2)

        warmup_ref =
          Process.send_after(
            self(),
            {:begin_zone, first_zone, first_runtime, "schedule", schedule.id, schedule.name},
            warmup * 1000
          )

        {:reply, :ok,
         %{
           state
           | master_ref: master_ref,
             queue: rest,
             schedule_id: schedule.id,
             schedule_name: schedule.name,
             warmup_timer_ref: warmup_ref
         }}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:stop, _from, state) do
    state = emergency_stop(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      active_zones: state.active_zones,
      queue_length: length(state.queue),
      schedule_id: state.schedule_id,
      schedule_name: state.schedule_name
    }

    {:reply, status, state}
  end

  # ── handle_info ───────────────────────────────────────────────────────────────

  @impl true
  def handle_info(
        {:begin_zone, zone, runtime_seconds, trigger, schedule_id, schedule_name},
        state
      ) do
    Logger.info(
      "[Runner] Starting zone '#{zone.name}' for #{runtime_seconds}s (pin #{zone.gpio_pin})"
    )

    case GPIO.open(zone.gpio_pin, :output) do
      {:ok, zone_ref} ->
        GPIO.write(zone_ref, 0)

        {:ok, session} =
          Watering.start_session(%{
            zone_id: zone.id,
            zone_name: zone.name,
            trigger: trigger,
            planned_duration_seconds: runtime_seconds
          })

        # Use zone_id in the timer message so we know which zone completed.
        timer_ref = Process.send_after(self(), {:zone_complete, zone.id}, runtime_seconds * 1000)
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        active = %{
          zone: zone,
          session: session,
          zone_ref: zone_ref,
          timer_ref: timer_ref,
          planned_seconds: runtime_seconds,
          started_at: now
        }

        broadcast(
          {:watering_started,
           %{
             zone_name: zone.name,
             zone_id: zone.id,
             planned_seconds: runtime_seconds,
             started_at: now,
             trigger: trigger,
             schedule_name: schedule_name,
             queue_length: length(state.queue)
           }}
        )

        {:noreply,
         %{
           state
           | active_zones: [active | state.active_zones],
             schedule_id: schedule_id,
             schedule_name: schedule_name,
             warmup_timer_ref: nil
         }}

      {:error, reason} ->
        Logger.error("[Runner] Failed to open zone pin #{zone.gpio_pin}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:zone_complete, zone_id}, state) do
    case Enum.find(state.active_zones, &(&1.zone.id == zone_id)) do
      nil ->
        # Already stopped manually; ignore the stale timer message.
        {:noreply, state}

      active ->
        actual_seconds = DateTime.diff(DateTime.utc_now(), active.started_at)
        GPIO.write(active.zone_ref, 1)
        GPIO.close(active.zone_ref)
        Logger.info("[Runner] Zone '#{active.zone.name}' complete (#{actual_seconds}s)")
        Watering.end_session(active.session)

        broadcast(
          {:zone_complete,
           %{
             zone_name: active.zone.name,
             zone_id: zone_id,
             actual_seconds: actual_seconds
           }}
        )

        new_active_zones = Enum.reject(state.active_zones, &(&1.zone.id == zone_id))
        state = %{state | active_zones: new_active_zones}

        case state.queue do
          [{next_zone, next_runtime} | remaining] ->
            # Next zone in schedule – master valve stays open
            Process.send_after(
              self(),
              {:begin_zone, next_zone, next_runtime, "schedule", state.schedule_id,
               state.schedule_name},
              500
            )

            {:noreply, %{state | queue: remaining}}

          [] ->
            {:noreply, maybe_close_master(state)}
        end
    end
  end

  @impl true
  def terminate(_reason, state) do
    emergency_stop(state)
    :ok
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  # Close master and broadcast schedule_complete only when nothing is running.
  defp maybe_close_master(%{active_zones: [], queue: []} = state) do
    close_master_valve(state.master_ref)

    if state.schedule_id do
      broadcast({:schedule_complete, %{schedule_name: state.schedule_name}})
      Logger.info("[Runner] Schedule '#{state.schedule_name}' complete")
    end

    %{state | master_ref: nil, schedule_id: nil, schedule_name: nil}
  end

  defp maybe_close_master(state), do: state

  defp open_master_valve(state) do
    if state.master_ref, do: close_master_valve(state.master_ref)

    master_pin = Settings.get_integer("master_valve_pin", 2)
    Logger.info("[Runner] Opening master valve (pin #{master_pin})")

    case GPIO.open(master_pin, :output) do
      {:ok, ref} ->
        GPIO.write(ref, 0)
        {:ok, ref}

      err ->
        err
    end
  end

  defp close_master_valve(nil), do: :ok

  defp close_master_valve(ref) do
    master_pin = Settings.get_integer("master_valve_pin", 2)
    Logger.info("[Runner] Closing master valve (pin #{master_pin})")
    GPIO.write(ref, 1)
    GPIO.close(ref)
  end

  defp emergency_stop(state) do
    # Cancel any pending warmup timer so the zone never opens after a stop.
    if state.warmup_timer_ref, do: Process.cancel_timer(state.warmup_timer_ref)

    # Stop every active zone.
    Enum.each(state.active_zones, fn active ->
      Process.cancel_timer(active.timer_ref)
      GPIO.write(active.zone_ref, 1)
      GPIO.close(active.zone_ref)
      actual = DateTime.diff(DateTime.utc_now(), active.started_at)
      Watering.end_session(active.session)

      broadcast(
        {:watering_stopped,
         %{zone_name: active.zone.name, zone_id: active.zone.id, actual_seconds: actual, reason: :manual}}
      )
    end)

    # If we were only in warmup (master open but no zone active yet), still
    # broadcast a stop so the LiveView clears its state.
    if state.active_zones == [] and state.master_ref != nil do
      broadcast({:watering_stopped, %{zone_name: nil, zone_id: nil, actual_seconds: 0, reason: :manual}})
    end

    close_master_valve(state.master_ref)

    %{
      state
      | active_zones: [],
        master_ref: nil,
        queue: [],
        schedule_id: nil,
        schedule_name: nil,
        warmup_timer_ref: nil
    }
  end
end
