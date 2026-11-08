defmodule Samgita.CodexHostsTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  alias Samgita.{CodexHosts, FakeCodexServer, Principal}
  alias Samgita.CodexHosts.{Connection, Runtime}
  alias Samgita.Domain.{CodexHost, DomainEvent}

  setup do
    server = FakeCodexServer.start()
    agent = agent_fixture(%{"runtime_driver" => "codex", "runtime_version" => "0.167.0"})
    Phoenix.PubSub.subscribe(Samgita.PubSub, Runtime.topic())

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Samgita.CodexHosts.ConnectionSupervisor),
          do: DynamicSupervisor.terminate_child(Samgita.CodexHosts.ConnectionSupervisor, pid)

      FakeCodexServer.stop(server)
    end)

    %{server: server, agent: agent}
  end

  defp configure(agent, attrs) do
    CodexHosts.configure(
      Principal.operator(),
      command(Map.merge(%{"agent_id" => agent["id"], "transport" => "websocket"}, attrs))
    )
  end

  defp enable(host) do
    CodexHosts.enable(
      Principal.operator(),
      host["id"],
      command(%{"expected_version" => host["version"]})
    )
  end

  defp with_runtime_enabled(_ctx) do
    previous = Application.get_env(:samgita, :codex_hosts)
    Application.put_env(:samgita, :codex_hosts, Keyword.put(previous, :enabled, true))
    on_exit(fn -> Application.put_env(:samgita, :codex_hosts, previous) end)
    :ok
  end

  defp await_status(id, state, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 3_000
    wait = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:codex_host_status, ^id, %{"state" => ^state} = status} -> status
      {:codex_host_status, ^id, _} -> await_status(id, state, deadline)
    after
      wait -> flunk("host #{id} did not reach #{state}; now #{inspect(Runtime.status(id))}")
    end
  end

  defp events(id, type),
    do:
      Repo.all(
        from e in DomainEvent,
          where: e.resource_id == ^id and e.type == ^type,
          order_by: e.created_at
      )

  describe "configuration" do
    test "creates a disabled host, replays by command_id and versions updates", %{
      agent: agent,
      server: server
    } do
      attrs =
        command(%{"agent_id" => agent["id"], "transport" => "websocket", "url" => server.url})

      assert {:ok, host} = CodexHosts.configure(Principal.operator(), attrs)
      assert host["enabled"] == false
      assert host["version"] == 1
      assert host["generation"] == 0
      assert host["status"] == %{"state" => "stopped"}
      assert {:ok, ^host} = CodexHosts.configure(Principal.operator(), attrs)
      assert [_] = events(host["id"], "codex_host.configured")

      assert {:error, %{code: :stale_version}} =
               configure(agent, %{
                 "url" => "wss://codex.example/app-server",
                 "expected_version" => 7
               })

      assert {:ok, updated} =
               configure(agent, %{
                 "url" => "wss://codex.example/app-server",
                 "expected_version" => 1
               })

      assert updated["version"] == 2
      assert updated["url"] == "wss://codex.example/app-server"
    end

    test "stores reference names only and rejects secret values or invalid endpoints", %{
      agent: agent
    } do
      for attrs <- [
            %{"url" => "http://codex.example/app-server"},
            %{"url" => "ws://user:pass@codex.example/app-server"},
            %{"url" => "ws://codex.example/app-server", "token" => "secret-value"},
            %{"url" => "ws://codex.example/app-server", "token_ref" => "bad ref"},
            %{"url" => "ws://codex.example/app-server", "connect_address" => "not-an-ip"},
            %{"transport" => "ssh", "url" => "ws://codex.example/app-server"}
          ] do
        assert {:error, %{code: :invalid}} = configure(agent, attrs)
      end

      assert {:ok, host} =
               configure(agent, %{
                 "url" => "wss://codex.example/app-server",
                 "token_ref" => "codex/prod-v1",
                 "connect_address" => "10.0.0.5"
               })

      assert host["token_ref"] == "codex/prod-v1"
      refute Repo.get!(CodexHost, host["id"]) |> Map.from_struct() |> inspect() =~ "secret-value"
    end

    test "only Codex runtime Agents can have a host" do
      other = agent_fixture(%{"name" => "Plain Agent"})

      assert {:error, %{code: :invalid}} =
               CodexHosts.configure(
                 Principal.operator(),
                 command(%{
                   "agent_id" => other["id"],
                   "transport" => "websocket",
                   "url" => "ws://localhost/app-server"
                 })
               )
    end
  end

  describe "runtime disabled" do
    test "enabling a host opens no connection while host runtime is off", %{
      agent: agent,
      server: server
    } do
      {:ok, host} = configure(agent, %{"url" => server.url})
      assert {:ok, %{"enabled" => true}} = enable(host)
      refute_receive {:fake_codex, :connected}, 300
      assert Runtime.whereis(host["id"]) == nil
      assert CodexHosts.status(host["id"]) == %{"state" => "stopped"}
    end
  end

  describe "connections" do
    setup :with_runtime_enabled

    test "connects, initializes and records a generation and server version", %{
      agent: agent,
      server: server
    } do
      {:ok, host} = configure(agent, %{"url" => server.url})
      {:ok, enabled} = enable(host)
      id = enabled["id"]

      assert_receive {:fake_codex, :request, "initialize"}, 3_000
      assert_receive {:fake_codex, :notification, "initialized"}, 3_000
      status = await_status(id, "connected")
      assert status["generation"] == 1
      assert status["server_version"] == "0.167.0"

      record = Repo.get!(CodexHost, id)
      assert record.generation == 1
      assert record.server_version == "0.167.0"
      assert record.last_connected_at
      assert record.version == enabled["version"]
      assert [event] = events(id, "codex_host.connected")
      assert event.data["generation"] == 1
      assert event.data["server_version"] == "0.167.0"
    end

    test "reconnects with a new generation after the server drops", %{
      agent: agent,
      server: server
    } do
      {:ok, host} = configure(agent, %{"url" => server.url})
      {:ok, _} = enable(host)
      id = host["id"]
      assert %{"generation" => 1} = await_status(id, "connected")

      FakeCodexServer.drop_connections(server)
      backoff = await_status(id, "backoff")
      assert backoff["retry_at"]
      assert %{"generation" => 2} = await_status(id, "connected")

      assert [disconnected] = events(id, "codex_host.disconnected")
      assert disconnected.data["generation"] == 1
      assert length(events(id, "codex_host.connected")) == 2
    end

    test "disabling stops the connection and prevents reconnects", %{agent: agent, server: server} do
      {:ok, host} = configure(agent, %{"url" => server.url})
      {:ok, enabled} = enable(host)
      id = host["id"]
      await_status(id, "connected")
      assert_receive {:fake_codex, :connected}, 1_000

      assert {:ok, %{"enabled" => false}} =
               CodexHosts.disable(
                 Principal.operator(),
                 id,
                 command(%{"expected_version" => enabled["version"]})
               )

      await_status(id, "stopped")
      assert Runtime.whereis(id) == nil
      assert_receive {:fake_codex, :closed}, 3_000
      refute_receive {:fake_codex, :connected}, 400
      assert [_] = events(id, "codex_host.disabled")
    end

    test "reconfiguring a running host restarts it with the new settings", %{
      agent: agent,
      server: server
    } do
      {:ok, host} = configure(agent, %{"url" => server.url})
      {:ok, enabled} = enable(host)
      id = host["id"]
      await_status(id, "connected")
      pid = Runtime.whereis(id)

      other = FakeCodexServer.start(version: "0.168.0")
      on_exit(fn -> FakeCodexServer.stop(other) end)

      {:ok, _} = configure(agent, %{"url" => other.url, "expected_version" => enabled["version"]})
      assert %{"server_version" => "0.168.0"} = await_status(id, "connected")
      refute Runtime.whereis(id) == pid
    end

    test "operator reconnect replaces the session", %{agent: agent, server: server} do
      {:ok, host} = configure(agent, %{"url" => server.url})
      {:ok, _} = enable(host)
      id = host["id"]
      assert %{"generation" => 1} = await_status(id, "connected")

      assert :ok = CodexHosts.reconnect(Principal.operator(), id)
      assert %{"generation" => 2} = await_status(id, "connected")
    end

    test "a missing credential reference backs off without contacting the server", %{
      agent: agent,
      server: server
    } do
      {:ok, host} = configure(agent, %{"url" => server.url, "token_ref" => "codex/missing-v1"})
      {:ok, _} = enable(host)

      assert %{"error" => "credential_unavailable"} = await_status(host["id"], "backoff")
      refute_receive {:fake_codex, :connected}, 200
    end

    test "a resolved token is sent and never appears in status or events", %{agent: agent} do
      secret = "fake-codex-token-#{System.unique_integer([:positive])}"
      server = FakeCodexServer.start(token: secret)
      on_exit(fn -> FakeCodexServer.stop(server) end)
      previous = Application.get_env(:samgita, :codex_host_secrets)
      Application.put_env(:samgita, :codex_host_secrets, %{"codex/test-v1" => secret})
      on_exit(fn -> Application.put_env(:samgita, :codex_host_secrets, previous || %{}) end)

      {:ok, host} = configure(agent, %{"url" => server.url, "token_ref" => "codex/test-v1"})
      {:ok, _} = enable(host)
      status = await_status(host["id"], "connected")

      refute inspect(status) =~ secret

      refute inspect(Repo.all(from e in DomainEvent, where: e.resource_id == ^host["id"])) =~
               secret
    end

    test "a rejected handshake backs off with a safe error code", %{agent: agent} do
      server = FakeCodexServer.start(token: "expected-token")
      on_exit(fn -> FakeCodexServer.stop(server) end)

      {:ok, host} = configure(agent, %{"url" => server.url})
      {:ok, _} = enable(host)

      assert_receive {:fake_codex, :rejected, _}, 3_000
      status = await_status(host["id"], "backoff")
      assert is_binary(status["error"])
      refute status["error"] =~ "expected-token"
    end
  end

  test "boot sync starts every enabled host", %{agent: agent, server: server} do
    {:ok, host} = configure(agent, %{"url" => server.url})
    {:ok, _} = enable(host)
    assert Runtime.whereis(host["id"]) == nil

    with_runtime_enabled(%{})
    Runtime.sync_all()
    assert %{"generation" => 1} = await_status(host["id"], "connected")
  end

  test "server version comes from the initialize user agent" do
    wire = fn agent -> %{"result" => %{"userAgent" => agent}} end

    assert Connection.server_version(wire.("codex_cli_rs/0.167.0 (Mac OS 15; arm64) x")) ==
             "0.167.0"

    assert Connection.server_version(wire.("samgita/1.2.3-beta.1 (Linux)")) == "1.2.3-beta.1"
    assert Connection.server_version(wire.("garbage")) == nil
    assert Connection.server_version(%{}) == nil
  end
end
