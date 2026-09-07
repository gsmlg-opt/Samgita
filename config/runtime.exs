import Config

api_keys =
  System.get_env("SAMGITA_API_KEYS", "")
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)
  |> Enum.reject(&(&1 == ""))

config :samgita, :api_keys, api_keys

if port = System.get_env("PORT") do
  config :samgita_web, SamgitaWeb.Endpoint, http: [port: String.to_integer(port)]
end

if config_env() == :prod do
  database_url = System.get_env("DATABASE_URL") || raise "DATABASE_URL is required"
  secret_key_base = System.get_env("SECRET_KEY_BASE") || raise "SECRET_KEY_BASE is required"
  if api_keys == [], do: raise("SAMGITA_API_KEYS must contain at least one API key")

  config :samgita, Samgita.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10")),
    socket_options: if(System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: [])

  host = System.get_env("PHX_HOST", "localhost")

  config :samgita_web, SamgitaWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "3110"))],
    secret_key_base: secret_key_base
end
