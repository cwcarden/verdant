defmodule Verdant.GPIO.StubAdapter do
  @moduledoc """
  GPIO stub for development on non-Pi hardware.
  Logs all pin operations instead of touching hardware.
  """
  @behaviour Verdant.GPIO.Adapter

  require Logger

  @impl true
  def open(pin, direction, _opts \\ []) do
    Logger.info("[GPIO] Open  pin=#{pin} dir=#{direction}")
    {:ok, {:stub_pin, pin}}
  end

  @impl true
  def write({:stub_pin, pin}, value) do
    label = if value == 0, do: "LOW  ◀ ACTIVE", else: "HIGH   inactive"
    Logger.info("[GPIO] Write pin=#{pin} → #{label}")
    :ok
  end

  @impl true
  def close({:stub_pin, pin}) do
    Logger.info("[GPIO] Close pin=#{pin}")
    :ok
  end
end
