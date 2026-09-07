import Config

db_host = System.get_env("PGHOST") || System.get_env("POSTGRES_HOST", "localhost")

db_connection =
  if String.starts_with?(db_host, "/"),
    do: [socket_dir: db_host],
    else: [hostname: db_host]

config :samgita,
       Samgita.Repo,
       [
         username: System.get_env("POSTGRES_USER", System.get_env("USER", "postgres")),
         password: System.get_env("POSTGRES_PASSWORD", ""),
         database: "samgita_hub_test#{System.get_env("MIX_TEST_PARTITION")}",
         port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
         pool: Ecto.Adapters.SQL.Sandbox,
         pool_size: 10
       ] ++ db_connection

config :samgita_web, SamgitaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 3112],
  secret_key_base: "R0hndBwWd37pDBs+AZIvydzVXqPXTZ8xDoMZPS0QTcdFbUSGfEdgXKyDJhJRtpBW",
  server: false

config :samgita, Oban, testing: :manual
config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
config :phoenix, sort_verified_routes_query_params: true
config :phoenix_live_view, enable_expensive_runtime_checks: true
