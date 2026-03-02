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

  def list_active_sessions do
    WateringSession
    |> where([s], is_nil(s.ended_at) and s.skipped == false)
    |> order_by(asc: :started_at)
    |> preload(:zone)
    |> Repo.all()
  end

  @doc """
  End any sessions that were left open by a previous process run (e.g. app restart
  while a zone was running). Called once on Runner startup.
  """
  def end_orphaned_sessions do
    require Logger
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      WateringSession
      |> where([s], is_nil(s.ended_at) and s.skipped == false)
      |> Repo.update_all(set: [ended_at: now])

    if count > 0 do
      Logger.info("[Watering] Cleaned up #{count} orphaned session(s) from a previous run")
    end

    :ok
  end

  @doc """
  Deletes watering sessions beyond the most recent `keep` records.
  Runs at startup and daily so the database stays bounded in size.
  Returns `{deleted_count, nil}`.
  """
  def prune_old_sessions(keep \\ 500) do
    keep_ids =
      WateringSession
      |> order_by(desc: :started_at)
      |> limit(^keep)
      |> select([s], s.id)
      |> Repo.all()

    if length(keep_ids) >= keep do
      {count, _} =
        WateringSession
        |> where([s], s.id not in ^keep_ids)
        |> Repo.delete_all()

      if count > 0 do
        require Logger
        Logger.info("[Watering] Pruned #{count} old session(s), retaining last #{keep}")
      end

      {count, nil}
    else
      {0, nil}
    end
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
