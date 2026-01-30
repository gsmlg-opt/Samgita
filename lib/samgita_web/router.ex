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
    plug SamgitaWeb.Plugs.RateLimit, limit: 100, window_ms: 60_000
  end

  scope "/", SamgitaWeb do
    pipe_through :browser

    live "/", DashboardLive.Index, :index
    live "/projects/new", ProjectFormLive.Index, :new
    live "/projects/:id", ProjectLive.Index, :show

    live "/agents", AgentsLive.Index, :index
    live "/mcp", McpLive.Index, :index
    live "/skills", SkillsLive.Index, :index
    live "/references", ReferencesLive.Index, :index
    live "/references/*filename", ReferencesLive.Show, :show
    live "/playground", PlaygroundLive.Index, :index
  end

  scope "/api", SamgitaWeb do
    pipe_through :api

    resources "/projects", ProjectController, except: [:new, :edit] do
      post "/pause", ProjectController, :pause
      post "/resume", ProjectController, :resume

      resources "/tasks", TaskController, only: [:index, :show] do
        post "/retry", TaskController, :retry
      end

      resources "/agents", AgentRunController, only: [:index, :show]
    end

    resources "/webhooks", WebhookController, only: [:index, :create, :delete]
  end
end
