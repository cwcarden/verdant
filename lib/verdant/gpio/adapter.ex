defmodule Verdant.GPIO.Adapter do
  @moduledoc "Behaviour that all GPIO adapters must implement."

  @type gpio :: any()

  @doc "Open a GPIO pin for output. Returns {:ok, gpio} or {:error, reason}."
  @callback open(pin :: non_neg_integer(), direction :: :input | :output, opts :: keyword()) ::
              {:ok, gpio()} | {:error, term()}

  @doc "Write a value to an open GPIO pin. 0 = LOW (relay active), 1 = HIGH (relay inactive)."
  @callback write(gpio :: gpio(), value :: 0 | 1) :: :ok | {:error, term()}

  @doc "Close and release a GPIO pin."
  @callback close(gpio :: gpio()) :: :ok
end
