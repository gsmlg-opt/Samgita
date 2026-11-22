defmodule Samgita.GitHub.PatCipher do
  @moduledoc false
  @purpose "samgita/github-pat/storage/v1"

  def key_base do
    case Application.get_env(:samgita, :github_pat_key_base) || System.get_env("SECRET_KEY_BASE") do
      key when is_binary(key) and byte_size(key) >= 32 -> {:ok, key}
      _ -> {:error, :storage_key_unavailable}
    end
  end

  def seal(token, id, account) do
    with {:ok, base} <- key_base() do
      nonce = :crypto.strong_rand_bytes(12)

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(
          :aes_256_gcm,
          key(base),
          nonce,
          token,
          aad(id, account),
          true
        )

      {:ok, <<1, nonce::binary, tag::binary, ciphertext::binary>>}
    end
  end

  def open(<<1, nonce::binary-12, tag::binary-16, ciphertext::binary>>, id, account) do
    with {:ok, base} <- key_base() do
      case :crypto.crypto_one_time_aead(
             :aes_256_gcm,
             key(base),
             nonce,
             ciphertext,
             aad(id, account),
             tag,
             false
           ) do
        token when is_binary(token) -> {:ok, token}
        :error -> {:error, :unreadable_token}
      end
    end
  end

  def open(_, _, _), do: {:error, :unreadable_token}

  defp key(base), do: :crypto.mac(:hmac, :sha256, base, @purpose)
  defp aad(id, account), do: "#{@purpose}/#{id}/#{account}"
end
