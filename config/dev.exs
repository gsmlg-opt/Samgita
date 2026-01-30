import Config

# Configure your database
config :samgita, Samgita.Repo,
  username: "gao",
  hostname: "localhost",
  database: "samgita_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :samgita, SamgitaWeb.Endpoint,
  http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: 3110],
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "Pj01A5h21DzggjKpnl3ezzFuxstdmjeKAAuyYMAM1nkKDzo5UF/oCYZnvE6i7nTk",
  watchers: [
    bun: {Bun, :install_and_run, [:samgita, ~w(--watch)]},
    tailwind: {Tailwind, :install_and_run, [:samgita, ~w(--watch)]}
  ]

# Reload browser tabs when matching files change.
config :samgita, SamgitaWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      # Static assets, except user uploads
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
      # Gettext translations
      ~r"priv/gettext/.*\.po$"E,
      # Router, Controllers, LiveViews and LiveComponents
      ~r"lib/samgita_web/router\.ex$"E,
      ~r"lib/samgita_web/(controllers|live|components)/.*\.(ex|heex)$"E
    ]
  ]

# Enable dev routes for dashboard and mailbox
config :samgita, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Include debug annotations and locations in rendered markup.
  # Changing this configuration will require mix clean and a full recompile.
  debug_heex_annotations: true,
  debug_attributes: true,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true
