defmodule SamgitaWeb.Router do
  use SamgitaWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SamgitaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug SamgitaWeb.Plugs.ApiAuth
    plug SamgitaWeb.Plugs.RateLimit, limit: 100, window_ms: 60_000
  end

  scope "/", SamgitaWeb do
    pipe_through :browser
    live "/", DashboardLive.Index, :index
  end

  scope "/api", SamgitaWeb do
    get "/health", HealthController, :index
    get "/info", InfoController, :index
  end
end
