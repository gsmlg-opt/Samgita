defmodule IndependentTransportConsumer.DirectHostTest do
  use ExUnit.Case
  alias SamgitaProtocolWebSocket.{Client, FakeAgent}

  test "direct session, replay, approvals and cancellation work without a platform" do
    host = start_supervised!({FakeAgent, token: "consumer-local-token", port: 0, owner: self()})

    {:ok, client} =
      Client.connect(FakeAgent.url(host),
        token: "consumer-local-token",
        capabilities: SamgitaProtocol.capabilities()
      )

    assert {:ok, _} = initialize(client)

    assert {:ok, %{"thread_id" => thread}} =
             request(client, "thread/start", %{"title" => "Direct host"})

    assert {:ok, %{"turn_id" => turn}} =
             request(client, "turn/start", %{
               "thread_id" => thread,
               "input" => [%{"type" => "text", "text" => "Simulation only"}]
             })

    assert {:ok, _} =
             request(client, "turn/steer", %{
               "thread_id" => thread,
               "turn_id" => turn,
               "input" => [%{"type" => "text", "text" => "Keep the simulation bounded"}]
             })

    assert :ok = FakeAgent.emit_delta(host, thread, turn, "No Samgita needed")

    assert_receive {:samgita_protocol, ^client,
                    {:notification, %{"method" => "item/delta", "cursor" => cursor}}},
                   1000

    assert :ok = Client.reconnect(client)
    assert {:ok, _} = initialize(client)
    assert {:ok, _} = request(client, "thread/resume", %{"thread_id" => thread})
    assert :ok = FakeAgent.emit_delta(host, thread, turn, "Resumed")

    assert {:ok, %{"events" => [%{"params" => %{"delta" => "Resumed"}}]}} =
             request(client, "stream/resume", %{
               "stream_id" => "thread:" <> thread,
               "cursor" => cursor
             })

    assert :ok = FakeAgent.request_approval(host, thread, turn, "explicit-approval")
    assert_receive {:samgita_protocol, ^client, {:request, approval}}, 1000

    assert :ok =
             Client.reply(
               client,
               approval,
               {:ok,
                %{"approval_id" => "explicit-approval", "decision" => "deny", "scope" => "once"}}
             )

    assert_receive {:fake_agent_approval, "explicit-approval", "deny"}, 1000

    assert {:ok, %{"status" => "interrupted"}} =
             request(client, "turn/interrupt", %{"thread_id" => thread, "turn_id" => turn})

    assert {:error, %{code: "conflict"}} =
             FakeAgent.emit_delta(host, thread, turn, "No longer running")

    loaded = Application.loaded_applications() |> Enum.map(&elem(&1, 0))
    refute Enum.any?(loaded, &(&1 in [:samgita, :samgita_web, :ecto_sql, :postgrex, :backplane]))
    assert Process.whereis(Samgita.Repo) == nil
    assert Process.whereis(Sigma.Supervisor) == nil
    Client.close(client)
  end

  defp initialize(client),
    do:
      request(client, "connection/initialize", %{
        "versions" => ["1.0"],
        "capabilities" => SamgitaProtocol.capabilities()
      })

  defp request(client, method, params) do
    id = Integer.to_string(System.unique_integer([:positive]))

    Client.request(client, method, params,
      id: id,
      command_id: "operation-" <> id,
      correlation_id: "correlation-" <> id
    )
  end
end
