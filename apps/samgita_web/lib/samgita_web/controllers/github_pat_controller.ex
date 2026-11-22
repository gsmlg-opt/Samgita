defmodule SamgitaWeb.GitHubPATController do
  use SamgitaWeb, :controller
  alias Samgita.GitHub.{Console, PatCipher}

  @purpose "samgita/github-pat/entry/v1"
  @lifetime 120

  # Only a public key and an encrypted, session-bound ticket leave this action.
  # The submitted token consequently never enters a conn or a LiveView event.
  def challenge(conn, params) do
    expected = params["version"]
    expected = if expected == "", do: nil, else: expected

    with {:ok, base} <- PatCipher.key_base(),
         {:ok, session} <- browser_session(conn),
         true <- expected == Console.version() do
      {public, private} = :crypto.generate_key(:ecdh, :secp256r1)

      ticket =
        Phoenix.Token.encrypt(base, @purpose, {session, expected, private}, max_age: @lifetime)

      reply(conn, 200, %{public_key: Base.url_encode64(public, padding: false), ticket: ticket})
    else
      false -> failure(conn, :stale)
      {:error, reason} -> failure(conn, reason)
    end
  end

  def create(conn, %{
        "ticket" => ticket,
        "public_key" => public,
        "nonce" => nonce,
        "ciphertext" => ciphertext
      })
      when is_binary(ticket) and byte_size(ticket) <= 1024 do
    with {:ok, base} <- PatCipher.key_base(),
         {:ok, session} <- browser_session(conn),
         {:ok, {^session, expected, private}} <-
           Phoenix.Token.decrypt(base, @purpose, ticket, max_age: @lifetime),
         {:ok, <<4, _::binary-64>> = public} <- decode(public, 88),
         {:ok, <<_::96>> = nonce} <- decode(nonce, 16),
         {:ok, sealed} when byte_size(sealed) in 17..8208 <- decode(ciphertext, 10_944),
         {:ok, token} <- open(ticket, private, public, nonce, sealed),
         :ok <- Console.connect(token, expected) do
      reply(conn, 200, %{saved: true})
    else
      {:error, reason} -> failure(conn, reason)
      _ -> failure(conn, :invalid_entry)
    end
  end

  def create(conn, _), do: failure(conn, :invalid_entry)

  defp browser_session(conn) do
    case get_session(conn, "_csrf_token") do
      token when is_binary(token) -> {:ok, :crypto.hash(:sha256, token)}
      _ -> {:error, :invalid_entry}
    end
  end

  defp decode(value, limit) when is_binary(value) and byte_size(value) <= limit,
    do: Base.url_decode64(value, padding: false)

  defp decode(_, _), do: :error

  defp open(ticket, private, public, nonce, sealed) do
    shared = :crypto.compute_key(:ecdh, public, private, :secp256r1)
    # HKDF-SHA256 with a single 32-byte output block, matching the browser envelope.
    extracted = :crypto.mac(:hmac, :sha256, nonce, shared)
    key = :crypto.mac(:hmac, :sha256, extracted, @purpose <> <<1>>)
    size = byte_size(sealed) - 16
    <<data::binary-size(size), tag::binary-16>> = sealed

    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, data, ticket, tag, false) do
      token when is_binary(token) -> {:ok, token}
      :error -> {:error, :invalid_entry}
    end
  rescue
    _ in [ArgumentError, ErlangError] -> {:error, :invalid_entry}
  end

  defp failure(conn, reason) do
    {status, message} =
      case reason do
        :storage_key_unavailable ->
          {503, gettext("Set a stable SECRET_KEY_BASE on the server before saving a PAT.")}

        :unapproved_destination ->
          {503,
           gettext("Configure the approved github.com API destination in SAMGITA_GITHUB_HOSTS.")}

        :stale ->
          {409, gettext("GitHub settings changed. Reload the page and try again.")}

        :invalid_token_input ->
          {422, gettext("Paste the full GitHub token value on a single line.")}

        :invalid_token ->
          {422,
           gettext("GitHub returned HTTP 401. Check that the full token is active on GitHub.")}

        :forbidden ->
          {422, gettext("GitHub could not read the account or its repositories with this PAT.")}

        {:rate_limited, until} ->
          {429,
           gettext("GitHub rate limit reached. Retry after %{time}.",
             time: DateTime.from_unix!(until) |> DateTime.to_string()
           )}

        reason when reason in [:invalid_entry, :invalid, :expired, :missing] ->
          {422, gettext("The entry session expired or could not be read. Enter the PAT again.")}

        _ ->
          {503, gettext("GitHub could not be reached. The previous configuration was preserved.")}
      end

    reply(conn, status, %{error: message})
  end

  defp reply(conn, status, payload),
    do:
      conn |> put_resp_header("cache-control", "no-store") |> put_status(status) |> json(payload)
end
