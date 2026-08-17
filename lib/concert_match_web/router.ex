defmodule ConcertMatchWeb.Router do
  use ConcertMatchWeb, :router

  import ConcertMatchWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ConcertMatchWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Outside the browser pipeline: a health check shouldn't need a session or
  # carry a CSRF token, and Render polls it constantly.
  scope "/", ConcertMatchWeb do
    get "/healthz", HealthController, :index
  end

  scope "/", ConcertMatchWeb do
    pipe_through :browser

    get "/", PageController, :home

    get "/auth/spotify", AuthController, :request
    get "/auth/spotify/callback", AuthController, :callback
    delete "/auth/logout", AuthController, :delete
  end

  scope "/", ConcertMatchWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated,
      on_mount: [{ConcertMatchWeb.UserAuth, :ensure_authenticated}] do
      live "/home", HomeLive
      live "/settings", SettingsLive
      live "/data", DataLive
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:concert_match, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ConcertMatchWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
