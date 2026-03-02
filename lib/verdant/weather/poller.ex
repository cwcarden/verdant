defmodule Verdant.Weather.Poller do
  @moduledoc """
  GenServer that periodically fetches weather data from the Ambient Weather API.

  The fetch interval is read from Settings at each tick so changes take effect
  without restarting the app. Defaults to 15 minutes if not configured.

  Broadcasts `{:weather_updated, reading}` on the "weather" PubSub topic after
  each successful fetch so connected LiveViews can refresh immediately.
  """

  use GenServer
  require Logger

  alias Verdant.{Weather, Settings}
  alias Phoenix.PubSub

  @pubsub Verdant.PubSub
  @topic "weather"

  @default_interval_minutes 15

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def subscribe, do: PubSub.subscribe(@pubsub, @topic)

  @impl true
  def init(_opts) do
    # Fetch immediately on startup (after a short delay so the repo is ready)
    Process.send_after(self(), :fetch, 5_000)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:fetch, state) do
    do_fetch()
    schedule_next()
    {:noreply, state}
  end

  defp do_fetch do
    case Weather.fetch_from_api() do
      {:ok, reading} ->
        Logger.info("[WeatherPoller] Fetched weather data successfully")
        PubSub.broadcast(@pubsub, @topic, {:weather_updated, reading})

      {:error, "Ambient Weather API not configured"} ->
        # Silently skip — user hasn't set up credentials yet
        :ok

      {:error, reason} ->
        Logger.warning("[WeatherPoller] Failed to fetch weather: #{inspect(reason)}")
    end
  end

  defp schedule_next do
    minutes = Settings.get_integer("weather_fetch_interval_minutes", @default_interval_minutes)
    # Clamp to a sane range: no faster than 5 min, no slower than 24h
    minutes = minutes |> max(5) |> min(1440)
    Process.send_after(self(), :fetch, minutes * 60_000)
  end
end
