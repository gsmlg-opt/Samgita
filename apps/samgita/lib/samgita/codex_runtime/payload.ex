defmodule Samgita.CodexRuntime.Payload do
  @moduledoc """
  Authenticated encryption for complete native payloads, isolated from audit data.

  Versioned keys are supplied by the deployment, never generated or stored in the
  database. Associated data binds ciphertext to its runtime, record and direction.
  Keyed fingerprints support idempotency without retaining a plaintext hash of a
  low-entropy secret. Losing a key makes its payloads unavailable, not executable.
  """
  alias Samgita.Error
  @limit 8_388_608

  def seal(value, associated_data) do
    with {:ok, id, key} <- active_key(),
         {:ok, json} <- encode(value) do
      nonce = :crypto.strong_rand_bytes(12)

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, json, associated_data, true)

      {:ok,
       %{
         "version" => 1,
         "key_id" => id,
         "nonce" => Base.encode64(nonce),
         "ciphertext" => Base.encode64(ciphertext),
         "tag" => Base.encode64(tag)
       }}
    end
  end

  def open(%{"version" => 1, "key_id" => id} = payload, associated_data) do
    with {:ok, key} <- key(id),
         {:ok, nonce} when byte_size(nonce) == 12 <- Base.decode64(payload["nonce"]),
         {:ok, ciphertext} when byte_size(ciphertext) <= @limit <-
           Base.decode64(payload["ciphertext"]),
         {:ok, tag} when byte_size(tag) == 16 <- Base.decode64(payload["tag"]),
         json when is_binary(json) <-
           :crypto.crypto_one_time_aead(
             :aes_256_gcm,
             key,
             nonce,
             ciphertext,
             associated_data,
             tag,
             false
           ),
         {:ok, value} <- Jason.decode(json) do
      {:ok, value}
    else
      {:error, %Error{} = error} -> {:error, error}
      _ -> error(:native_payload_unreadable)
    end
  rescue
    _ in [ArgumentError, FunctionClauseError] -> error(:native_payload_unreadable)
  end

  def open(_, _), do: error(:native_payload_unreadable)

  def fingerprint(value, id \\ nil) do
    with {:ok, active_id, active_key} <- fingerprint_key(id),
         {:ok, _json} <- encode(value) do
      digest = Samgita.Commands.digest(value)
      mac = :crypto.mac(:hmac, :sha256, active_key, "native-fingerprint-v1:" <> digest)
      {:ok, active_id <> ":" <> Base.encode64(mac)}
    end
  end

  def aad(runtime_id, record_id, slot),
    do: Jason.encode!(["samgita.native.v1", runtime_id, record_id, slot])

  defp encode(value) do
    case Jason.encode(value) do
      {:ok, json} when byte_size(json) <= @limit -> {:ok, json}
      _ -> error(:invalid_native_payload)
    end
  end

  defp fingerprint_key(nil), do: active_key()

  defp fingerprint_key(id) do
    with {:ok, value} <- key(id), do: {:ok, id, value}
  end

  defp active_key do
    id = Application.get_env(:samgita, :native_payload_key_id)
    with {:ok, value} <- key(id), do: {:ok, id, value}
  end

  defp key(id) when is_binary(id) do
    value = Map.get(Application.get_env(:samgita, :native_payload_keys, %{}), id)

    if is_binary(value) && byte_size(value) == 32,
      do: {:ok, value},
      else: error(:native_payload_key_unavailable)
  end

  defp key(_), do: error(:native_payload_key_unavailable)
  defp error(code), do: {:error, Error.new(code)}
end
