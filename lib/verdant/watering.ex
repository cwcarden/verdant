defmodule Verdant.Watering do
  import Ecto.Query
  alias Verdant.Repo
  alias Verdant.Watering.WateringSession

  def list_recent_sessions(limit \\ 50) do
    WateringSession
    |> order_by(desc: :started_at)
    |> limit(^limit)
    |> preload(:zone)
    |> Repo.all()
  end

  def start_session(attrs) do
    attrs = Map.put(attrs, :started_at, DateTime.utc_now() |> DateTime.truncate(:second))
    %WateringSession{}
    |> WateringSession.changeset(attrs)
    |> Repo.insert()
  end

  def end_session(%WateringSession{} = session) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    actual = DateTime.diff(now, session.started_at)
    session
    |> WateringSession.changeset(%{ended_at: now, actual_duration_seconds: actual})
    |> Repo.update()
  end

  def get_active_session do
    WateringSession
    |> where([s], is_nil(s.ended_at) and s.skipped == false)
    |> order_by(desc: :started_at)
    |> limit(1)
    |> preload(:zone)
    |> Repo.one()
  end

  def today_usage do
    today = DateTime.utc_now() |> DateTime.to_date()
    start_of_day = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")

    WateringSession
    |> where([s], s.started_at >= ^start_of_day and not s.skipped)
    |> select([s], sum(s.actual_duration_seconds))
    |> Repo.one() || 0
  end
end
