defmodule SamgitaWeb.Router do
  use SamgitaWeb, :router

  import SamgitaWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SamgitaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
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

  ## Authentication routes

  scope "/", SamgitaWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{SamgitaWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", SamgitaWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{SamgitaWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
