defmodule VerdantWeb.Router do
  use VerdantWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {VerdantWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", VerdantWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
    live "/manual", ManualLive, :index
    live "/schedules", SchedulesLive, :index
    live "/zones", ZonesLive, :index
    live "/weather", WeatherLive, :index
    live "/history", HistoryLive, :index
    live "/settings", SettingsLive, :index
  end

  if Application.compile_env(:verdant, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: VerdantWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
