import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :samgita, Samgita.Repo,
  username: "gao",
  hostname: "localhost",
  database: "samgita_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :samgita, SamgitaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 3112],
  secret_key_base: "R0hndBwWd37pDBs+AZIvydzVXqPXTZ8xDoMZPS0QTcdFbUSGfEdgXKyDJhJRtpBW",
  server: false

# Disable Oban queues during test
config :samgita, Oban, testing: :inline

# Use echo as a mock for Claude CLI in tests
config :samgita, :claude_command, "echo"

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
