defmodule Verdant.Irrigation.Runner do
  @moduledoc """
  GenServer that manages the active irrigation cycle.

  Responsibilities:
  - Open/close GPIO pins for master valve and zone relays
  - Log watering sessions to the database
  - Sequence multiple zones for schedule runs
  - Broadcast state changes over PubSub so LiveViews update in real time

  Pin logic (active-LOW relays):
  - write(ref, 0) → valve OPEN  (relay energized)
  - write(ref, 1) → valve CLOSED (relay de-energized)

  Sequence for a zone run:
  1. Open master valve (GPIO 2 default)
  2. Wait warmup_seconds (keeps pressure stable)
  3. Open zone valve
  4. After runtime_seconds: close zone valve
  5. If more zones queued → open next zone (master stays open)
  6. When all zones done → close master valve
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

  @doc "Start a single zone manually. Returns :ok or {:error, :busy | :disabled}."
  def start_zone(zone, runtime_seconds) do
    GenServer.call(__MODULE__, {:start_zone, zone, runtime_seconds})
  end

  @doc """
  Start a schedule run. zones_with_times is a list of {%Zone{}, runtime_seconds}.
  Returns :ok or {:error, reason}.
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
    state = %{
      master_ref: nil,
      # %{zone, session, zone_ref, timer_ref, planned_seconds, started_at}
      active: nil,
      # [{zone, runtime_seconds}] remaining in schedule
      queue: [],
      schedule_id: nil,
      schedule_name: nil
    }

    {:ok, state}
  end

  # ── handle_call ──────────────────────────────────────────────────────────────

  @impl true
  def handle_call({:start_zone, _zone, _runtime_seconds}, _from, %{active: active} = state)
      when not is_nil(active) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call({:start_zone, _zone, _runtime_seconds} = msg, _from, state) do
    {:start_zone, zone, runtime_seconds} = msg

    case open_master_valve(state) do
      {:ok, master_ref} ->
        warmup = Settings.get_integer("master_valve_warmup_seconds", 2)

        Process.send_after(
          self(),
          {:begin_zone, zone, runtime_seconds, "manual", nil, nil},
          warmup * 1000
        )

        {:reply, :ok, %{state | master_ref: master_ref, queue: []}}

      {:error, reason} ->
        Logger.error("[Runner] Failed to open master valve: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:start_schedule, _schedule, []}, _from, state) do
    {:reply, {:error, :no_zones}, state}
  end

  def handle_call({:start_schedule, _schedule, _zones}, _from, %{active: active} = state)
      when not is_nil(active) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call({:start_schedule, schedule, [{first_zone, first_runtime} | rest]}, _from, state) do
    case open_master_valve(state) do
      {:ok, master_ref} ->
        warmup = Settings.get_integer("master_valve_warmup_seconds", 2)

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
             schedule_name: schedule.name
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
      active: state.active,
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
        # open zone valve (active LOW)
        GPIO.write(zone_ref, 0)

        {:ok, session} =
          Watering.start_session(%{
            zone_id: zone.id,
            zone_name: zone.name,
            trigger: trigger,
            planned_duration_seconds: runtime_seconds
          })

        timer_ref = Process.send_after(self(), :zone_complete, runtime_seconds * 1000)
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
         %{state | active: active, schedule_id: schedule_id, schedule_name: schedule_name}}

      {:error, reason} ->
        Logger.error("[Runner] Failed to open zone pin #{zone.gpio_pin}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:zone_complete, %{active: nil} = state), do: {:noreply, state}

  def handle_info(:zone_complete, state) do
    %{active: active, queue: queue} = state
    actual_seconds = DateTime.diff(DateTime.utc_now(), active.started_at)

    # Close zone valve
    GPIO.write(active.zone_ref, 1)
    GPIO.close(active.zone_ref)
    Logger.info("[Runner] Zone '#{active.zone.name}' complete (#{actual_seconds}s)")

    # Log session end
    Watering.end_session(active.session)

    broadcast(
      {:zone_complete,
       %{
         zone_name: active.zone.name,
         zone_id: active.zone.id,
         actual_seconds: actual_seconds
       }}
    )

    state = %{state | active: nil}

    case queue do
      [{next_zone, next_runtime} | remaining] ->
        # Next zone in schedule – master valve stays open
        Process.send_after(
          self(),
          {:begin_zone, next_zone, next_runtime, "schedule", state.schedule_id,
           state.schedule_name},
          # 500ms gap between zones
          500
        )

        {:noreply, %{state | queue: remaining}}

      [] ->
        # All zones done – close master valve
        close_master_valve(state.master_ref)

        if state.schedule_id do
          broadcast({:schedule_complete, %{schedule_name: state.schedule_name}})
          Logger.info("[Runner] Schedule '#{state.schedule_name}' complete")
        end

        {:noreply, %{state | master_ref: nil, schedule_id: nil, schedule_name: nil}}
    end
  end

  @impl true
  def terminate(_reason, state) do
    emergency_stop(state)
    :ok
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp open_master_valve(state) do
    # If master is already open (e.g. restart scenario), close it first
    if state.master_ref, do: close_master_valve(state.master_ref)

    master_pin = Settings.get_integer("master_valve_pin", 2)
    Logger.info("[Runner] Opening master valve (pin #{master_pin})")

    case GPIO.open(master_pin, :output) do
      {:ok, ref} ->
        # open master valve
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

  defp emergency_stop(%{active: nil, master_ref: nil} = state), do: state

  defp emergency_stop(state) do
    # Cancel timer
    if state.active && state.active.timer_ref do
      Process.cancel_timer(state.active.timer_ref)
    end

    # Close zone valve
    if state.active do
      GPIO.write(state.active.zone_ref, 1)
      GPIO.close(state.active.zone_ref)
      actual = DateTime.diff(DateTime.utc_now(), state.active.started_at)
      Watering.end_session(state.active.session)

      broadcast(
        {:watering_stopped,
         %{zone_name: state.active.zone.name, actual_seconds: actual, reason: :manual}}
      )
    end

    # Close master valve
    close_master_valve(state.master_ref)

    %{state | active: nil, master_ref: nil, queue: [], schedule_id: nil, schedule_name: nil}
  end
end
