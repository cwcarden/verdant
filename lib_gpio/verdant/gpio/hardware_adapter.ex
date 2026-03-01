defmodule Verdant.GPIO.HardwareAdapter do
  @moduledoc """
  Real GPIO adapter using Circuits.GPIO.
  Only compiled in the :prod environment (see elixirc_paths in mix.exs).
  Relays are active-LOW: write(ref, 0) opens the valve, write(ref, 1) closes it.
  """
  @behaviour Verdant.GPIO.Adapter

  @impl true
  def open(pin, direction, opts \\ []) do
    # Start HIGH so relays remain inactive on startup
    Circuits.GPIO.open(pin, direction, Keyword.merge([initial_value: 1], opts))
  end

  @impl true
  def write(gpio, value), do: Circuits.GPIO.write(gpio, value)

  @impl true
  def close(gpio), do: Circuits.GPIO.close(gpio)
end
