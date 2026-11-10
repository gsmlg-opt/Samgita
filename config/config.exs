import Config

config :samgita,
  ecto_repos: [Samgita.Repo],
  generators: [timestamp_type: :utc_datetime]

config :samgita_web, SamgitaWeb.Endpoint,
  url: [host: "samgita.local"],
  adapter: Gaoxy.PhoenixAdapter,
  websocket_paths: [
    "/live/websocket",
    "/phoenix/live_reload/socket/websocket",
    "/@duskmoon_bundler/ws"
  ],
  render_errors: [
    formats: [html: SamgitaWeb.ErrorHTML, json: SamgitaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Samgita.PubSub,
  live_view: [signing_salt: "sVrxWKHP"]

config :duskmoon_bundler, :samgita_web,
  root: Path.expand("../apps/samgita_web/assets", __DIR__),
  entry: Path.expand("../apps/samgita_web/assets/js/app.ts", __DIR__),
  outdir: Path.expand("../apps/samgita_web/priv/static/assets", __DIR__),
  resolve_dirs: [Path.expand("../deps", __DIR__)],
  target: :es2020,
  format: :esm,
  sourcemap: :hidden,
  tailwind: [
    css: Path.expand("../apps/samgita_web/assets/css/app.css", __DIR__),
    sources: [
      %{base: Path.expand("../apps/samgita_web/lib", __DIR__), pattern: "**/*.{ex,heex}"},
      %{base: Path.expand("../apps/samgita_web/assets", __DIR__), pattern: "**/*.{css,js,ts}"},
      %{base: Path.expand("../deps/phoenix_duskmoon/lib", __DIR__), pattern: "**/*.{ex,heex}"},
      # Utility classes used by the DuskMoon React chat (dm_react_chat).
      %{
        base: Path.expand("../deps/phoenix_duskmoon/assets/js/react_chat", __DIR__),
        pattern: "**/*.js"
      }
    ]
  ],
  server: [
    prefix: "/assets",
    watch_dirs: [
      Path.expand("../apps/samgita_web/lib", __DIR__),
      Path.expand("../apps/samgita_web/assets", __DIR__)
    ]
  ]

config :duskmoon_bundler_runtime, :samgita_web, outdir: "priv/static/assets"

config :samgita, Styx,
  repo: Samgita.Repo,
  queues: [hub_events: 10, hub_schedules: 1, hub_maintenance: 1, hub_github: 2],
  cron: [
    crontab: [
      {"* * * * *", Samgita.Workers.ScheduleTickWorker},
      {"* * * * *", Samgita.Workers.CoordinationMaintenanceWorker},
      {"* * * * *", Samgita.Workers.GitHubMaintenanceWorker}
    ]
  ],
  pruner: false,
  lifeline: false,
  reindexer: false

config :tzdata, :autoupdate, :disabled

config :samgita, :api_keys, []

# Codex app-server host connections (design §11).
config :samgita, :codex_hosts, enabled: true

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :phoenix, :filter_parameters, [
  "native",
  "dispatch_token",
  "request_payload",
  "response_payload",
  "native_payload",
  "endpoint_url",
  "endpoint_metadata",
  "password",
  "credential",
  "token",
  "authorization",
  "secret",
  "proof",
  "api_key",
  "private_key",
  "webhook_secret"
]

import_config "#{config_env()}.exs"
