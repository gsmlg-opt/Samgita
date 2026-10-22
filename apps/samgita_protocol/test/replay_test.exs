defmodule SamgitaProtocol.ReplayTest do
  use ExUnit.Case, async: true
  alias SamgitaProtocol.{Client, Error, Replay}

  defp notification,
    do: SamgitaProtocol.TestFixtures.notification(1) |> Map.drop(["stream_id", "cursor"])

  test "bounded replay returns ordered retained notifications and explicit gaps" do
    {:ok, log} = Replay.new("stream-1", limit: 2)
    {:ok, first, log} = Replay.append(log, notification())
    {:ok, second, log} = Replay.append(log, notification())
    assert {:ok, [^first, ^second]} = Replay.since(log, 0)
    {:ok, third, log} = Replay.append(log, notification())

    assert {:error, %Error{code: "replay_gap", details: %{"earliest_cursor" => 1}}} =
             Replay.since(log, 0)

    assert {:ok, [^second, ^third]} = Replay.since(log, 1)
    assert {:ok, []} = Replay.since(log, 3)
    assert {:error, %Error{code: "replay_gap"}} = Replay.since(log, 4)
    assert {:error, %Error{}} = Replay.append(log, %{first | "stream_id" => "other"})
  end

  test "large retained logs replay in bounded schema-sized pages" do
    {:ok, log} = Replay.new("stream-1", limit: 200)

    log =
      Enum.reduce(1..130, log, fn _, acc ->
        {:ok, _, next} = Replay.append(acc, notification())
        next
      end)

    assert {:ok, page} = Replay.since(log, 0)
    assert length(page) == 128

    assert {:ok, [%{"cursor" => 129}, %{"cursor" => 130}]} =
             Replay.since(log, List.last(page)["cursor"])
  end

  test "restored checkpoints replay only after processing, with duplicates and gaps explicit" do
    client = SamgitaProtocol.TestFixtures.ready()
    {:ok, _, client} = Client.receive(client, SamgitaProtocol.TestFixtures.notification(1))
    assert Client.checkpoints(client) == %{"stream-1" => 0}
    {[_], client} = Client.drain(client, 1)
    {:ok, client} = Client.ack_cursor(client, "stream-1", 1)
    checkpoint = Client.checkpoints(client)
    {:ok, fresh} = Client.new(capabilities: ["streaming.v1"], checkpoints: checkpoint)
    fresh = Client.establish(fresh, ["streaming.v1"], "new-connection")
    assert Client.replay_cursor(fresh, "stream-1") == 1
    assert {:ok, [], ^fresh} = Client.receive(fresh, SamgitaProtocol.TestFixtures.notification(1))

    assert {:error, %Error{code: "replay_gap"}, ^fresh} =
             Client.receive(fresh, SamgitaProtocol.TestFixtures.notification(3))

    assert {:ok, [_], fresh} = Client.receive(fresh, SamgitaProtocol.TestFixtures.notification(2))
    assert {:ok, [], ^fresh} = Client.receive(fresh, SamgitaProtocol.TestFixtures.notification(2))
    changed = put_in(SamgitaProtocol.TestFixtures.notification(2), ["params", "delta"], "changed")
    assert {:error, %Error{code: "conflict"}, ^fresh} = Client.receive(fresh, changed)

    for checkpoints <- [%{"s" => -1}, %{"" => 1}, %{"s" => "1"}] do
      assert {:error, %Error{code: "invalid_params"}} = Client.new(checkpoints: checkpoints)
    end
  end

  test "same-process reconnect retains unprocessed notifications and never advances the checkpoint" do
    client = SamgitaProtocol.TestFixtures.ready()
    {:ok, _, client} = Client.receive(client, SamgitaProtocol.TestFixtures.notification(1))
    {:ok, [], client} = Client.disconnect(client)
    {:ok, client} = Client.reconnect(client)
    assert Client.replay_cursor(client, "stream-1") == 0
    {[message], client} = Client.drain(client, 1)
    assert message["cursor"] == 1
    assert {:ok, _} = Client.ack_cursor(client, "stream-1", 1)
  end

  test "stream resume rejects mixed-stream, missing or unordered replay events" do
    client = SamgitaProtocol.TestFixtures.ready()

    {:ok, request, client} =
      Client.request(client, "stream/resume", %{"stream_id" => "stream-1", "cursor" => 0})

    for events <- [
          [SamgitaProtocol.TestFixtures.notification(2)],
          [Map.put(SamgitaProtocol.TestFixtures.notification(1), "stream_id", "other")]
        ] do
      reply =
        SamgitaProtocol.TestFixtures.response(request, %{
          "stream_id" => "stream-1",
          "cursor" => 2,
          "events" => events
        })

      assert {:error, %Error{code: "invalid_response"}, ^client} = Client.receive(client, reply)
    end
  end

  test "explicit replay ingestion dispatches retained events through the normal processed checkpoint" do
    client = SamgitaProtocol.TestFixtures.ready()

    result = %{
      "stream_id" => "stream-1",
      "cursor" => 2,
      "events" => [
        SamgitaProtocol.TestFixtures.notification(1),
        SamgitaProtocol.TestFixtures.notification(2)
      ]
    }

    assert {:ok, [{:notification, _}, {:notification, _}], client} =
             Client.receive_replay(client, result)

    assert Client.replay_cursor(client, "stream-1") == 0
    {messages, client} = Client.drain(client, 10)
    assert length(messages) == 2
    {:ok, client} = Client.ack_cursor(client, "stream-1", 2)

    assert {:ok, [{:notification, _}], _} =
             Client.receive(client, SamgitaProtocol.TestFixtures.notification(3))

    limited = SamgitaProtocol.TestFixtures.ready(max_buffer: 1)

    assert {:error, %Error{code: "buffer_full"}, ^limited} =
             Client.receive_replay(limited, result)
  end
end
