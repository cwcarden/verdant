defmodule Verdant.Repo do
  use Ecto.Repo,
    otp_app: :verdant,
    adapter: Ecto.Adapters.SQLite3
end
