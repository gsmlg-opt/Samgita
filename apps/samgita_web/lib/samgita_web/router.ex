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
    plug :operator_principal
  end

  pipeline :agent_api do
    plug :accepts, ["json"]
    plug SamgitaWeb.Plugs.AgentAuth
    plug SamgitaWeb.Plugs.RateLimit, limit: 100, window_ms: 60_000
  end

  pipeline :agent_connect do
    plug :accepts, ["json"]
    plug SamgitaWeb.Plugs.AgentAuth, require_connection: false
    plug SamgitaWeb.Plugs.RateLimit, limit: 100, window_ms: 60_000
  end

  pipeline :github_ingress do
    plug :accepts, ["json"]
    plug SamgitaWeb.Plugs.RateLimit, limit: 100, window_ms: 60_000
  end

  scope "/api/github", SamgitaWeb do
    pipe_through :github_ingress
    post "/webhooks/:connection_id", GitHubWebhookController, :create
  end

  scope "/", SamgitaWeb do
    pipe_through :browser
    live "/", DashboardLive.Index, :index
    live "/agents", AgentsLive.Index, :index
    live "/agents/:id", AgentsLive.Show, :show
    live "/projects", ProjectsLive.Index, :index
    live "/projects/:id", ProjectsLive.Show, :show
    live "/projects/:project_id/tasks/:id", TasksLive.Show, :show
  end

  scope "/api", SamgitaWeb do
    get "/health", HealthController, :index
    get "/info", InfoController, :index
  end

  scope "/api", SamgitaWeb do
    pipe_through :api

    resources "/projects", ProjectController, only: [:index, :show, :create, :update]
    post "/projects/:project_id/transition", ProjectController, :transition
    get "/projects/:project_id/context", ProjectController, :context
    get "/github/connections", GitHubController, :connections
    post "/github/connections", GitHubController, :configure
    get "/projects/:project_id/github/repositories", GitHubController, :mappings
    post "/projects/:project_id/github/repositories", GitHubController, :associate
    patch "/projects/:project_id/github/repositories/:id", GitHubController, :update
    get "/projects/:project_id/github/repositories/:id/facts", GitHubController, :facts

    get "/projects/:project_id/github/repositories/:id/observations/:observation_id",
        GitHubController,
        :observation

    get "/projects/:project_id/github/repositories/:id/deliveries/:delivery_id",
        GitHubController,
        :delivery

    post "/projects/:project_id/github/repositories/:id/reconcile", GitHubController, :reconcile
    post "/projects/:project_id/members", ProjectController, :put_member

    resources "/agents", AgentController, only: [:index, :show, :create, :update]
    post "/agents/:agent_id/credentials", AgentController, :put_credential

    post "/agents/:agent_id/credentials/:credential_id/revoke",
         AgentController,
         :revoke_credential

    get "/projects/:project_id/repositories", RepositoryController, :index
    post "/projects/:project_id/repositories", RepositoryController, :create
    get "/projects/:project_id/sessions", ExecutionSessionController, :index
    post "/projects/:project_id/sessions", ExecutionSessionController, :create

    resources "/projects/:project_id/tasks", TaskController,
      only: [:index, :show, :create, :update]

    post "/projects/:project_id/tasks/:task_id/transition", TaskController, :transition
    post "/projects/:project_id/tasks/:task_id/adopt", TaskController, :adopt
    post "/projects/:project_id/tasks/:task_id/decisions", TaskController, :decide
    post "/projects/:project_id/tasks/:task_id/artifacts", TaskController, :add_artifact
    post "/projects/:project_id/attempts/:id/resolve", AttemptController, :resolve

    get "/projects/:project_id/codex-runtimes", CodexRuntimeController, :index
    get "/projects/:project_id/codex-runtimes/:id", CodexRuntimeController, :show
    get "/projects/:project_id/codex-runtimes/:id/operations", CodexRuntimeController, :operations
    get "/projects/:project_id/codex-runtimes/:id/events", CodexRuntimeController, :events

    get "/projects/:project_id/codex-runtimes/:id/operations/:operation_id/native",
        CodexRuntimeController,
        :native_operation

    get "/projects/:project_id/codex-runtimes/:id/events/:event_id/native",
        CodexRuntimeController,
        :native_event

    post "/projects/:project_id/codex-runtimes/:id/events/:event_id/reply",
         CodexRuntimeController,
         :reply

    post "/projects/:project_id/codex-runtimes/:id/operations/:operation_id/cancel",
         CodexRuntimeController,
         :cancel

    post "/projects/:project_id/codex-runtimes/:id/operations/:operation_id/reconcile",
         CodexRuntimeController,
         :reconcile

    post "/projects/:project_id/codex-runtimes/:id/attest-cessation",
         CodexRuntimeController,
         :attest_cessation

    get "/projects/:project_id/events", EventController, :index
    post "/projects/:project_id/events/trigger", EventController, :trigger
    post "/projects/:project_id/events/external", EventController, :external
    post "/projects/:project_id/events/:event_id/redeliver", EventController, :redeliver
    get "/projects/:project_id/event-routing", EventController, :routing
    put "/projects/:project_id/event-routing", EventController, :configure
    get "/projects/:project_id/deliveries", EventController, :deliveries
    get "/projects/:project_id/deliveries/:id", EventController, :delivery
    post "/projects/:project_id/deliveries/:id/recover", EventController, :recover
    get "/projects/:project_id/schedules", ScheduleController, :index
    post "/projects/:project_id/schedules", ScheduleController, :create
    patch "/projects/:project_id/schedules/:id", ScheduleController, :update

    get "/platform", PlatformController, :show
    post "/platform/activate", PlatformController, :activate
    post "/platform/close", PlatformController, :close
  end

  scope "/api/agent", SamgitaWeb do
    pipe_through :agent_connect
    post "/connect", AgentController, :connect
  end

  scope "/api/agent", SamgitaWeb do
    pipe_through :agent_api

    get "/projects/:project_id/github/repositories", GitHubController, :mappings
    get "/projects/:project_id/github/repositories/:id/facts", GitHubController, :facts

    get "/projects/:project_id/github/repositories/:id/observations/:observation_id",
        GitHubController,
        :observation

    get "/projects/:project_id/github/repositories/:id/deliveries/:delivery_id",
        GitHubController,
        :delivery

    resources "/projects", ProjectController, only: [:index, :show, :update]
    post "/projects/:project_id/transition", ProjectController, :transition
    get "/projects/:project_id/context", ProjectController, :context
    get "/projects/:project_id/repositories", RepositoryController, :index
    post "/projects/:project_id/repositories", RepositoryController, :create
    get "/projects/:project_id/sessions", ExecutionSessionController, :index
    post "/projects/:project_id/sessions", ExecutionSessionController, :create

    resources "/projects/:project_id/tasks", TaskController,
      only: [:index, :show, :create, :update]

    post "/projects/:project_id/tasks/:task_id/transition", TaskController, :transition
    post "/projects/:project_id/tasks/:task_id/decisions", TaskController, :decide
    post "/projects/:project_id/tasks/:task_id/artifacts", TaskController, :add_artifact
    post "/projects/:project_id/tasks/:task_id/claim", AttemptController, :claim
    post "/projects/:project_id/attempts/:id/start", AttemptController, :start
    post "/projects/:project_id/attempts/:id/renew", AttemptController, :renew
    post "/projects/:project_id/attempts/:id/progress", AttemptController, :progress
    post "/projects/:project_id/attempts/:id/report", AttemptController, :report
    post "/projects/:project_id/attempts/:id/rebind", AttemptController, :rebind
    post "/projects/:project_id/attempts/:id/resolve", AttemptController, :resolve
    get "/projects/:project_id/attempts/:id/proof", AttemptController, :proof

    get "/projects/:project_id/codex-runtimes", CodexRuntimeController, :index
    post "/projects/:project_id/codex-runtimes", CodexRuntimeController, :create
    get "/projects/:project_id/codex-runtimes/:id", CodexRuntimeController, :show
    get "/projects/:project_id/codex-runtimes/:id/operations", CodexRuntimeController, :operations
    post "/projects/:project_id/codex-runtimes/:id/operations", CodexRuntimeController, :prepare
    get "/projects/:project_id/codex-runtimes/:id/events", CodexRuntimeController, :events
    post "/projects/:project_id/codex-runtimes/:id/events", CodexRuntimeController, :record_event

    post "/projects/:project_id/codex-runtimes/:id/events/:event_id/reply",
         CodexRuntimeController,
         :reply

    post "/projects/:project_id/codex-runtimes/:id/operations/:operation_id/dispatch",
         CodexRuntimeController,
         :dispatch

    post "/projects/:project_id/codex-runtimes/:id/operations/:operation_id/settle",
         CodexRuntimeController,
         :settle

    post "/projects/:project_id/codex-runtimes/:id/operations/:operation_id/cancel",
         CodexRuntimeController,
         :cancel

    post "/projects/:project_id/codex-runtimes/:id/reconnect", CodexRuntimeController, :reconnect

    get "/projects/:project_id/codex-runtimes/:id/operations/:operation_id/native",
        CodexRuntimeController,
        :native_operation

    get "/projects/:project_id/codex-runtimes/:id/events/:event_id/native",
        CodexRuntimeController,
        :native_event

    get "/projects/:project_id/events", EventController, :index
    post "/projects/:project_id/events/trigger", EventController, :trigger
    get "/projects/:project_id/event-routing", EventController, :routing
    post "/projects/:project_id/event-routing/:subscription_id/ack", EventController, :ack_cursor
    get "/projects/:project_id/deliveries", EventController, :deliveries
    get "/projects/:project_id/deliveries/:id", EventController, :delivery
    post "/projects/:project_id/deliveries/:id/report", EventController, :report
    get "/projects/:project_id/schedules", ScheduleController, :index
  end

  defp operator_principal(conn, _opts) do
    machine_credential? =
      Enum.any?(get_req_header(conn, "authorization"), &String.match?(&1, ~r/^bearer /i))

    if machine_credential? and Application.get_env(:samgita, :api_keys, []) == [] do
      conn
      |> SamgitaWeb.FallbackController.call({:error, Samgita.Error.new(:forbidden)})
      |> halt()
    else
      assign(conn, :samgita_principal, Samgita.Principal.operator())
    end
  end
end
