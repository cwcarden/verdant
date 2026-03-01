defmodule Verdant.LocalTime do
  @moduledoc """
  Helpers for working with the user-configured local timezone.

  All times stored in the database are UTC. Use these helpers to convert
  them to the timezone configured in Settings → System → Timezone before
  displaying to the user.
  """

  alias Verdant.Settings

  @default_tz "America/Chicago"

  @doc "Returns the IANA timezone string from settings (e.g. \"America/Chicago\")."
  def timezone do
    Settings.get("timezone", @default_tz)
  end

  @doc "Returns the current DateTime in the configured local timezone."
  def now do
    DateTime.now!(timezone())
  end

  @doc "Converts a UTC DateTime (or naive UTC DateTime) to the configured local timezone."
  def to_local(%DateTime{} = utc) do
    DateTime.shift_zone!(utc, timezone())
  end

  def to_local(%NaiveDateTime{} = utc_naive) do
    utc_naive
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.shift_zone!(timezone())
  end

  @doc "Returns today's Date in the configured local timezone."
  def today do
    now() |> DateTime.to_date()
  end

  @doc """
  Formats a UTC DateTime for display using the configured timezone.
  Default format shows 12-hour clock + AM/PM.
  """
  def format(%DateTime{} = utc, fmt \\ "%I:%M %p") do
    utc |> to_local() |> Calendar.strftime(fmt)
  end

  @doc "List of {display_label, iana_timezone} tuples for the timezone selector."
  def us_timezones do
    [
      {"Eastern (ET) — New York, Miami", "America/New_York"},
      {"Central (CT) — Chicago, Dallas", "America/Chicago"},
      {"Mountain (MT) — Denver, Salt Lake City", "America/Denver"},
      {"Mountain — Arizona (no DST)", "America/Phoenix"},
      {"Pacific (PT) — Los Angeles, Seattle", "America/Los_Angeles"},
      {"Alaska (AKT) — Anchorage", "America/Anchorage"},
      {"Hawaii (HST) — Honolulu", "America/Honolulu"}
    ]
  end
end
