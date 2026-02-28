import Config

# SamgitaProvider configuration
# Anthropic API key used by samgita_memory for Voyage embeddings
config :samgita_provider,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY")

# API Authentication
# Configure valid API keys for REST API access
# Multiple keys can be provided as comma-separated values
api_keys_string = System.get_env("SAMGITA_API_KEYS", "")

config :samgita, :api_keys,
  if(api_keys_string == "",
    do: [],
    else: String.split(api_keys_string, ",") |> Enum.map(&String.trim/1)
  )

config :samgita_web, SamgitaWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "3110"))]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :samgita, Samgita.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # SamgitaMemory shares the same database in production
  config :samgita_memory, SamgitaMemory.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("MEMORY_POOL_SIZE") || "5"),
    socket_options: maybe_ipv6,
    types: SamgitaMemory.PostgrexTypes

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :samgita, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :samgita_web, SamgitaWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base
end
