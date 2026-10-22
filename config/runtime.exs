import Config

api_keys =
  System.get_env("SAMGITA_API_KEYS", "")
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)
  |> Enum.reject(&(&1 == ""))

config :samgita, :api_keys, api_keys

if encoded_destinations = System.get_env("SAMGITA_EVENT_DESTINATIONS") do
  with {:ok, values} when is_map(values) <- Jason.decode(encoded_destinations) do
    destinations =
      Map.new(values, fn {agent_id, value} ->
        with %{"url" => url, "addresses" => addresses} <- value,
             true <- is_binary(url) && is_list(addresses) && addresses != [] do
          pins =
            Enum.map(addresses, fn address ->
              with true <- is_binary(address),
                   {:ok, pin} <- :inet.parse_address(String.to_charlist(address)) do
                pin
              else
                _ -> raise "SAMGITA_EVENT_DESTINATIONS requires explicit IP addresses"
              end
            end)

          {agent_id,
           %{url: url, addresses: pins, allow_insecure: value["allow_insecure"] == true}}
        else
          _ -> raise "SAMGITA_EVENT_DESTINATIONS requires Agent IDs, exact URLs and IP addresses"
        end
      end)

    config :samgita, :event_destinations, destinations
  else
    _ -> raise "SAMGITA_EVENT_DESTINATIONS must be a JSON object"
  end
end

if encoded_credentials = System.get_env("SAMGITA_EVENT_CREDENTIALS") do
  with {:ok, values} when is_map(values) <- Jason.decode(encoded_credentials),
       true <-
         Enum.all?(values, fn {reference, token} ->
           is_binary(reference) && is_binary(token) && byte_size(token) in 1..8192 &&
             !String.contains?(token, ["\r", "\n"])
         end) do
    config :samgita, :event_credentials, values
  else
    _ -> raise "SAMGITA_EVENT_CREDENTIALS must map references to service credentials"
  end
end

if encoded_keys = System.get_env("SAMGITA_LEASE_KEYS") do
  with {:ok, values} when is_map(values) <- Jason.decode(encoded_keys),
       true <- map_size(values) > 0 do
    keys =
      Map.new(values, fn {id, encoded} ->
        with true <- is_binary(id) && Regex.match?(~r/\A[A-Za-z0-9_-]{1,100}\z/, id),
             true <- is_binary(encoded),
             {:ok, key} <- Base.decode64(encoded),
             true <- byte_size(key) >= 32 do
          {id, key}
        else
          _ -> raise "SAMGITA_LEASE_KEYS must contain named base64 keys of at least 32 bytes"
        end
      end)

    active = System.get_env("SAMGITA_LEASE_KEY_ID")
    if !Map.has_key?(keys, active), do: raise("SAMGITA_LEASE_KEY_ID must name a configured key")
    config :samgita, :lease_keys, keys
    config :samgita, :lease_key_id, active
  else
    _ -> raise "SAMGITA_LEASE_KEYS must be a nonempty JSON object"
  end
end

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
