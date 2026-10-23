defmodule SamgitaWeb.PlugCryptoRegressionTest do
  use ExUnit.Case, async: true

  alias Plug.Crypto.{MessageEncryptor, MessageVerifier}

  test "signed and encrypted messages reject tampering and different keys" do
    payload = "synthetic-token-payload"
    secret = :crypto.strong_rand_bytes(32)
    other = :crypto.strong_rand_bytes(32)

    for digest <- [:sha256, :sha384, :sha512] do
      signed = MessageVerifier.sign(payload, secret, digest)
      assert {:ok, ^payload} = MessageVerifier.verify(signed, secret)
      assert :error = MessageVerifier.verify(signed <> "tampered", secret)
      assert :error = MessageVerifier.verify(signed, other)
      assert :error = MessageVerifier.verify("malformed", secret)
    end

    encrypted = MessageEncryptor.encrypt(payload, "fixture-aad", secret, "")
    assert {:ok, ^payload} = MessageEncryptor.decrypt(encrypted, "fixture-aad", secret, "")
    assert :error = MessageEncryptor.decrypt(encrypted <> "tampered", "fixture-aad", secret, "")
    assert :error = MessageEncryptor.decrypt(encrypted, "different-aad", secret, "")
    assert :error = MessageEncryptor.decrypt(encrypted, "fixture-aad", other, "")
  end

  test "Phoenix tokens preserve scope, expiry and authenticated encryption" do
    endpoint = SamgitaWeb.Endpoint
    data = %{connection_id: "synthetic-connection"}
    token = Phoenix.Token.sign(endpoint, "fixture-salt", data)
    assert {:ok, ^data} = Phoenix.Token.verify(endpoint, "fixture-salt", token, max_age: 60)
    assert {:error, :invalid} = Phoenix.Token.verify(endpoint, "other-salt", token, max_age: 60)

    expired = Phoenix.Token.sign(endpoint, "fixture-salt", data, signed_at: 1)

    assert {:error, :expired} =
             Phoenix.Token.verify(endpoint, "fixture-salt", expired, max_age: 1)

    encrypted = Phoenix.Token.encrypt(endpoint, "fixture-salt", data)
    assert {:ok, ^data} = Phoenix.Token.decrypt(endpoint, "fixture-salt", encrypted, max_age: 60)

    assert {:error, :invalid} =
             Phoenix.Token.decrypt(endpoint, "other-salt", encrypted, max_age: 60)
  end

  test "signed browser sessions survive a round trip and reject a modified cookie" do
    options = Plug.Session.init(store: :cookie, key: "_fixture", signing_salt: "fixture-session")
    secret = String.duplicate("synthetic-key-base-", 4)

    response =
      %{Plug.Test.conn(:get, "/") | secret_key_base: secret}
      |> Plug.Session.call(options)
      |> Plug.Conn.fetch_session()
      |> Plug.Conn.put_session(:fixture_state, "csrf-fixture")
      |> Plug.Conn.send_resp(200, "ok")

    cookie = response.resp_cookies["_fixture"].value
    assert session_value(cookie, secret, options) == "csrf-fixture"
    assert session_value(cookie <> "tampered", secret, options) == nil
  end

  test "wrong argument types raise generic errors without secret arguments in stacktraces" do
    canary = "synthetic-crypto-error-canary-#{System.unique_integer([:positive])}"

    calls = [
      {MessageVerifier, :sign, [canary, %{invalid: true}]},
      {MessageVerifier, :verify, [%{invalid: true}, canary]},
      {MessageEncryptor, :encrypt, [canary, %{invalid: true}, ""]},
      {MessageEncryptor, :decrypt, [%{invalid: true}, canary, ""]},
      {Plug.Crypto, :secure_compare, [canary, %{invalid: true}]},
      {Plug.Crypto, :mask, [canary, %{invalid: true}]},
      {Plug.Crypto, :masked_compare, [canary, %{invalid: true}, "mask"]}
    ]

    for {module, function, args} <- calls do
      try do
        apply(module, function, args)
        flunk("wrong-typed crypto call unexpectedly succeeded")
      rescue
        error in ArgumentError ->
          trace = __STACKTRACE__
          refute Exception.format(:error, error, trace) =~ canary
          refute :erlang.term_to_binary({error, trace}) =~ canary
      end
    end
  end

  defp session_value(cookie, secret, options) do
    %{Plug.Test.conn(:get, "/") | secret_key_base: secret}
    |> Plug.Test.put_req_cookie("_fixture", cookie)
    |> Plug.Session.call(options)
    |> Plug.Conn.fetch_session()
    |> Plug.Conn.get_session(:fixture_state)
  end
end
