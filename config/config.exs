# General application configuration
import Config

config :samgita,
  ecto_repos: [Samgita.Repo],
  generators: [timestamp_type: :utc_datetime]

config :samgita_memory,
  ecto_repos: [SamgitaMemory.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :samgita_web, SamgitaWeb.Endpoint,
  check_origin: false,
  url: [host: "samgita.local"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SamgitaWeb.ErrorHTML, json: SamgitaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Samgita.PubSub,
  live_view: [signing_salt: "sVrxWKHP"]

# Configure bun (the version is required)
config :bun,
  version: "1.1.42",
  samgita_web: [
    args: ~w(build assets/js/app.ts --outdir=priv/static/assets/js --target=browser),
    cd: Path.expand("../apps/samgita_web", __DIR__)
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  samgita_web: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("../apps/samgita_web", __DIR__)
  ]

# Configure Swoosh to use Finch
config :swoosh, :api_client, Swoosh.ApiClient.Finch
config :swoosh, :finch_name, Samgita.Finch

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

# Configure SamgitaProvider
config :samgita_provider, provider: SamgitaProvider.ClaudeCode

# API keys (override in runtime.exs for production)
config :samgita, :api_keys, []

# Configure Oban for SamgitaMemory
config :samgita_memory, Oban,
  name: SamgitaMemory.Oban,
  repo: SamgitaMemory.Repo,
  queues: [
    embeddings: [limit: 5],
    compaction: [limit: 2],
    summarization: [limit: 3]
  ],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       # Run confidence decay + pruning daily at 3 AM
       {"0 3 * * *", SamgitaMemory.Workers.Compaction, args: %{action: "decay_and_prune"}}
     ]}
  ]

# Configure SamgitaMemory defaults
config :samgita_memory,
  embedding_provider: :anthropic,
  embedding_dimensions: 1536,
  retrieval_default_limit: 10,
  retrieval_min_confidence: 0.3,
  retrieval_semantic_weight: 0.7,
  retrieval_recency_weight: 0.2,
  retrieval_access_weight: 0.1,
  cache_max_memories: 10_000,
  cache_max_prd_executions: 100

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
