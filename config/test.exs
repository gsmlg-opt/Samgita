import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.

# Supports Unix socket (devenv) via PGHOST env var, or TCP via hostname
db_socket_opts =
  case System.get_env("PGHOST") do
    nil ->
      [
        hostname: System.get_env("POSTGRES_HOST", "localhost"),
        port: String.to_integer(System.get_env("POSTGRES_PORT", "5432"))
      ]

    pghost when is_binary(pghost) ->
      port = String.to_integer(System.get_env("POSTGRES_PORT", "5432"))

      if String.starts_with?(pghost, "/"),
        do: [socket_dir: pghost, port: port],
        else: [hostname: pghost, port: port]
  end

config :samgita,
       Samgita.Repo,
       [
         username: System.get_env("POSTGRES_USER", System.get_env("USER", "postgres")),
         password: System.get_env("POSTGRES_PASSWORD", ""),
         database: "samgita_test#{System.get_env("MIX_TEST_PARTITION")}",
         pool: Ecto.Adapters.SQL.Sandbox,
         pool_size: 10
       ] ++ db_socket_opts

config :samgita_memory,
       SamgitaMemory.Repo,
       [
         username: System.get_env("POSTGRES_USER", System.get_env("USER", "postgres")),
         password: System.get_env("POSTGRES_PASSWORD", ""),
         database: "samgita_test#{System.get_env("MIX_TEST_PARTITION")}",
         pool: Ecto.Adapters.SQL.Sandbox,
         pool_size: 10,
         types: SamgitaMemory.PostgrexTypes
       ] ++ db_socket_opts

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :samgita_web, SamgitaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 3112],
  secret_key_base: "R0hndBwWd37pDBs+AZIvydzVXqPXTZ8xDoMZPS0QTcdFbUSGfEdgXKyDJhJRtpBW",
  server: false

# Disable Oban queues during test
config :samgita, Oban, testing: :inline
config :samgita_memory, Oban, testing: :inline

# Use Mox-based mock provider for SamgitaProvider in tests
config :samgita_provider, provider: SamgitaProvider.MockProvider

# Use Mox-based mock for ObanClient in tests (default stub delegates to real Oban)
config :samgita, :oban_module, Samgita.MockOban

# Skip orchestrator notification retries in tests to avoid 500ms×N blocking
# when gen_statem processes are not registered in Horde (test isolation)
config :samgita, :bootstrap_notify_retries, 0
config :samgita, :orchestrator_notify_retries, 0

# Skip project recovery on startup (Repo sandbox isn't available to the Recovery GenServer)
config :samgita, :skip_recovery, true

# Use mock embedding provider in tests
config :samgita_memory, embedding_provider: :mock

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Configure Swoosh mailer for tests
config :samgita, Samgita.Mailer, adapter: Swoosh.Adapters.Test
