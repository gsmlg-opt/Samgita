import Config

config :samgita,
  ecto_repos: [Samgita.Repo],
  generators: [timestamp_type: :utc_datetime]

config :samgita_web, SamgitaWeb.Endpoint,
  url: [host: "samgita.local"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SamgitaWeb.ErrorHTML, json: SamgitaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Samgita.PubSub,
  live_view: [signing_salt: "sVrxWKHP"]

config :bun,
  version: "1.3.13",
  path: System.get_env("MIX_BUN_PATH"),
  packages: [
    args: ~w(install --frozen-lockfile),
    cd: Path.expand("../apps/samgita_web", __DIR__)
  ],
  samgita_web: [
    args: ~w(build assets/js/app.ts --outdir=priv/static/assets/js --target=browser),
    cd: Path.expand("../apps/samgita_web", __DIR__)
  ]

config :tailwind,
  version: "4.3.1",
  path: System.get_env("MIX_TAILWIND_PATH"),
  samgita_web: [
    args: ~w(--input=assets/css/app.css --output=priv/static/assets/css/app.css),
    cd: Path.expand("../apps/samgita_web", __DIR__)
  ]

config :samgita, Oban,
  repo: Samgita.Repo,
  queues: [hub_events: 10, hub_schedules: 1, hub_maintenance: 1, hub_github: 2],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", Samgita.Workers.ScheduleTickWorker},
       {"* * * * *", Samgita.Workers.CoordinationMaintenanceWorker},
       {"* * * * *", Samgita.Workers.GitHubMaintenanceWorker}
     ]}
  ]

config :tzdata, :autoupdate, :disabled

config :samgita, :api_keys, []

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
