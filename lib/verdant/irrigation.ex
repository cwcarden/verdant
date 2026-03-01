defmodule Verdant.Irrigation do
  @moduledoc "Public API for irrigation control."

  alias Verdant.Irrigation.Runner

  defdelegate start_zone(zone, runtime_seconds), to: Runner
  defdelegate stop_zone(zone_id), to: Runner
  defdelegate start_schedule(schedule, zones_with_times), to: Runner
  defdelegate stop_all(), to: Runner
  defdelegate status(), to: Runner
  defdelegate subscribe(), to: Runner
  defdelegate broadcast(msg), to: Runner
end
