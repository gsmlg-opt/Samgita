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
    live "/projects/new", ProjectFormLive.Index, :new
    live "/projects/:id", ProjectLive.Index, :show
    live "/projects/:project_id/prds/new", PrdChatLive.Index, :new
    live "/projects/:project_id/prds/:prd_id", PrdChatLive.Index, :edit

    live "/agents", AgentsLive.Index, :index
    live "/mcp", McpLive.Index, :index
    live "/skills", SkillsLive.Index, :index
    live "/references", ReferencesLive.Index, :index
    live "/references/*filename", ReferencesLive.Show, :show
  end

  scope "/api", SamgitaWeb do
    get "/health", HealthController, :index
    get "/info", InfoController, :index
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

    resources "/notifications", NotificationController,
      only: [:index, :show, :create, :update, :delete]

    resources "/features", FeatureController, except: [:new, :edit] do
      post "/enable", FeatureController, :enable
      post "/disable", FeatureController, :disable
      post "/archive", FeatureController, :archive
    end
  end
end
