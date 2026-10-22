defmodule Samgita.GitHub.Signature do
  @moduledoc "Verifies a GitHub SHA-256 signature over the exact bounded raw request body."

  @max_body_bytes 1_048_576

  @spec verify(binary(), term(), binary()) :: :ok | {:error, :invalid_signature}
  def verify(raw, "sha256=" <> hex, secret)
      when is_binary(raw) and byte_size(raw) <= @max_body_bytes and is_binary(secret) and
             byte_size(secret) > 0 and byte_size(hex) == 64 do
    with {:ok, signature} <- Base.decode16(hex, case: :mixed),
         true <- :crypto.hash_equals(:crypto.mac(:hmac, :sha256, secret, raw), signature) do
      :ok
    else
      _ -> {:error, :invalid_signature}
    end
  end

  def verify(_, _, _), do: {:error, :invalid_signature}
end
