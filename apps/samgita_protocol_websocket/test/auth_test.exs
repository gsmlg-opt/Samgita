defmodule SamgitaProtocolWebSocket.AuthTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolWebSocket.Client
  alias SamgitaProtocolWebSocket.Server

  test "the upgrade rejects missing and invalid bearer credentials before handler dispatch" do
    owner = self()

    listener =
      start_supervised!(
        {Server,
         port: 0,
         authenticate: fn token ->
           send(owner, {:authenticated, token})
           if token == "test-credential", do: {:ok, %{id: "machine-1"}}, else: :error
         end,
         handler: __MODULE__.Handler,
         handler_state: owner}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(listener)
    url = "ws://127.0.0.1:#{port}/app-server"

    assert {:error, %{code: "unauthorized"}} = Client.connect(url, token: "invalid")
    assert_received {:authenticated, "invalid"}
    refute_received :handler_called
    assert {:error, %{code: "unauthorized"}} = Client.connect(url)
    refute_received :handler_called

    assert {:ok, client} = Client.connect(url, token: "test-credential")
    assert_received {:authenticated, "test-credential"}
    assert :ok = Client.reconnect(client)
    assert_received {:authenticated, "test-credential"}
    Client.close(client)
  end

  test "credentials in URLs and insecure remote URLs are rejected" do
    assert {:error, %{code: "invalid_params"}} =
             Client.connect("ws://user:password@localhost/app-server", token: "secret")

    assert {:error, %{code: "invalid_params"}} =
             Client.connect("ws://localhost/app-server?token=secret", token: "secret")

    assert {:error, %{code: "invalid_params"}} =
             Client.connect("ws://example.org/app-server", token: "secret")
  end

  defmodule Handler do
    def capabilities, do: []
    def methods, do: []

    def handle_request(_method, _params, _context, owner) do
      send(owner, :handler_called)
      {:ok, %{}, owner}
    end
  end
end
