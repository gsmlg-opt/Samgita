# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :samgita,
  ecto_repos: [Samgita.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :samgita, SamgitaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SamgitaWeb.ErrorHTML, json: SamgitaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Samgita.PubSub,
  live_view: [signing_salt: "sVrxWKHP"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  samgita: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  samgita: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Oban
config :samgita, Oban,
  repo: Samgita.Repo,
  queues: [
    agent_tasks: [limit: 100],
    orchestration: [limit: 10],
    snapshots: [limit: 5]
  ]

# Configure Claude CLI command
config :samgita, :claude_command, "claude"

# API keys (override in runtime.exs for production)
config :samgita, :api_keys, []

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
