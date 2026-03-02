defmodule VerdantWeb.SessionController do
  @moduledoc """
  Handles PIN unlock session management.

  LockLive cannot write to the Plug session directly (LiveView limitation),
  so after a correct PIN entry it signs a short-lived Phoenix.Token and
  redirects here. This controller verifies the token and writes
  `unlocked_until` into the session.
  """

  use VerdantWeb, :controller

  @token_salt "pin_unlock"
  @token_max_age 15

  @doc """
  Called after LockLive verifies a correct PIN.
  Expects `?token=...&return_to=...` query params.
  Verifies the short-lived token, sets `unlocked_until` in the session,
  then redirects to the original destination.
  """
  def unlock(conn, %{"token" => token} = params) do
    return_to = Map.get(params, "return_to", "/")

    case Phoenix.Token.verify(VerdantWeb.Endpoint, @token_salt, token, max_age: @token_max_age) do
      {:ok, :verified} ->
        minutes = Verdant.Settings.get_integer("auto_lock_minutes", 30)

        # If auto_lock_minutes is 0 treat as "never" — use a far-future timestamp
        unlocked_until =
          if minutes > 0 do
            System.system_time(:second) + minutes * 60
          else
            System.system_time(:second) + 365 * 24 * 60 * 60
          end

        conn
        |> put_session(:unlocked_until, unlocked_until)
        |> redirect(to: safe_return_path(return_to))

      {:error, _} ->
        # Token invalid or expired — send back to lock screen
        redirect(conn, to: "/lock")
    end
  end

  def unlock(conn, _params) do
    redirect(conn, to: "/lock")
  end

  @doc """
  Manually locks the app — clears `unlocked_until` and redirects to lock screen.
  """
  def lock(conn, _params) do
    conn
    |> delete_session(:unlocked_until)
    |> redirect(to: "/lock")
  end

  # Prevent open redirect: only allow paths starting with /
  defp safe_return_path("/" <> _ = path), do: path
  defp safe_return_path(_), do: "/"

  @doc """
  Returns the token salt, for use by LockLive when signing the unlock token.
  """
  def token_salt, do: @token_salt
end
