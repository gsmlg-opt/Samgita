defmodule SamgitaProtocolWebSocket.DestinationTest do
  use ExUnit.Case, async: true
  alias SamgitaProtocolWebSocket.Client

  test "a pinned address bypasses DNS while retaining the URL Host" do
    listener =
      start_supervised!(%{
        id: :pinned_listener,
        start:
          {Bandit, :start_link,
           [
             [
               plug: {__MODULE__.HostPlug, self()},
               ip: {127, 0, 0, 1},
               port: 0,
               startup_log: false
             ]
           ]}
      })

    {:ok, {_address, port}} = ThousandIsland.listener_info(listener)

    assert {:ok, client} =
             Client.connect("ws://pinned.invalid:#{port}/app-server",
               allow_insecure: true,
               connect_address: {127, 0, 0, 1},
               token: "fake-credential"
             )

    assert_receive {:request_host, "pinned.invalid"}
    Client.close(client)
  end

  test "429 failed upgrades preserve safe status and retry delay without following redirects" do
    listener =
      start_supervised!(%{
        id: :limited_listener,
        start:
          {Bandit, :start_link,
           [[plug: __MODULE__.LimitedPlug, ip: {127, 0, 0, 1}, port: 0, startup_log: false]]}
      })

    {:ok, {_address, port}} = ThousandIsland.listener_info(listener)

    assert {:error,
            %{
              code: "upstream_error",
              details: %{"http_status" => 429, "retry_after" => "9000"}
            }} = Client.connect("ws://127.0.0.1:#{port}/app-server", token: "private-token")
  end

  test "invalid pin tuples are rejected before dialing" do
    for pin <- [{127, 0, 0, 999}, {1, 2}, "127.0.0.1"] do
      assert {:error, %{code: "invalid_params"}} =
               Client.connect("ws://127.0.0.1/app-server", connect_address: pin)
    end
  end

  defmodule HostPlug do
    def init(owner), do: owner

    def call(conn, owner) do
      send(owner, {:request_host, conn.host})

      SamgitaProtocolWebSocket.Plug.call(conn,
        handler: __MODULE__.Handler,
        authenticate: fn "fake-credential" -> {:ok, %{id: "fake"}} end
      )
    end

    defmodule Handler do
      def capabilities, do: []
      def methods, do: []
      def handle_request(_, _, _, state), do: {:ok, %{}, state}
    end
  end

  defmodule LimitedPlug do
    import Plug.Conn
    def init(opts), do: opts

    def call(conn, _opts) do
      conn
      |> put_resp_header("retry-after", "9000")
      |> put_resp_header("location", "http://must-not-follow.invalid/")
      |> send_resp(429, "Rate limited")
    end
  end
end
