defmodule VerdantWeb.Plugs.RequirePin do
  @moduledoc """
  Plug that enforces PIN lock on all protected routes.

  If PIN lock is enabled and a valid PIN is configured, checks the session
  for an `unlocked_until` timestamp. If expired (or absent), saves the
  requested path in the session and redirects to the lock screen.

  Also assigns `auto_lock_minutes` to `conn.assigns` so the root layout
  can inject it into a meta tag for the client-side idle timer.
  """

  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    pin_enabled = Verdant.Settings.get_bool("pin_lock_enabled", false)
    pin_code = Verdant.Settings.get("pin_code", "")
    auto_lock_minutes = Verdant.Settings.get_integer("auto_lock_minutes", 30)

    if pin_enabled and pin_code != "" do
      conn = assign(conn, :auto_lock_minutes, auto_lock_minutes)
      unlocked_until = get_session(conn, :unlocked_until)
      now = System.system_time(:second)

      if unlocked_until && unlocked_until > now do
        conn
      else
        conn
        |> put_session(:return_to, conn.request_path)
        |> redirect(to: "/lock")
        |> halt()
      end
    else
      conn
    end
  end
end
