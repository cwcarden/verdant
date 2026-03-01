defmodule Verdant.GPIO do
  @moduledoc "Public GPIO interface. Dispatches to the configured adapter."

  def adapter do
    Application.get_env(:verdant, :gpio_adapter, Verdant.GPIO.StubAdapter)
  end

  def open(pin, direction, opts \\ []), do: adapter().open(pin, direction, opts)
  def write(gpio, value), do: adapter().write(gpio, value)
  def close(gpio), do: adapter().close(gpio)
end
