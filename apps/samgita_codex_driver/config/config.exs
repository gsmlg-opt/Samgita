import Config

schema_mode =
  case System.get_env("SAMGITA_CODEX_SCHEMA_MODE", "compatible") do
    "compatible" -> :compatible
    "strict" -> :strict
    _ -> raise "SAMGITA_CODEX_SCHEMA_MODE must be compatible or strict"
  end

config :samgita_codex_driver, schema_mode: schema_mode
