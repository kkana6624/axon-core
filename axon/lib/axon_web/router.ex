defmodule AxonWeb.Router do
  use AxonWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AxonWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AxonWeb do
    pipe_through :browser

    get "/setup", SetupController, :index
    get "/", PageController, :home

    live "/macro", MacroLive

    if Mix.env() == :test do
      live "/__test__/remote_address", TestRemoteAddressLive
      live "/__test__/macro", MacroLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", AxonWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:axon, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AxonWeb.Telemetry
    end
  end
end
