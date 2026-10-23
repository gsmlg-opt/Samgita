defmodule SamgitaProtocol.TestFixtures do
  @moduledoc false
  alias SamgitaProtocol.Client

  def ready(opts \\ []) do
    {:ok, client} =
      Client.new(
        Keyword.merge([capabilities: ["sessions.v1", "streaming.v1", "approvals.v1"]], opts)
      )

    {:ok, request, client} =
      Client.request(
        client,
        "connection/initialize",
        %{
          "versions" => ["1.0"],
          "capabilities" => ["sessions.v1", "streaming.v1", "approvals.v1"]
        },
        id: "init"
      )

    response =
      response(request, %{
        "version" => "1.0",
        "capabilities" => ["sessions.v1", "streaming.v1", "approvals.v1"],
        "connection_id" => "conn-1"
      })

    {:ok, _, client} = Client.receive(client, response)
    client
  end

  def response(request, result) do
    request
    |> Map.drop(["method", "params"])
    |> Map.put("type", "response")
    |> Map.put("result", result)
  end

  def notification(cursor) do
    %{
      "schema_version" => "1.0",
      "type" => "notification",
      "correlation_id" => "flow-1",
      "method" => "item/delta",
      "stream_id" => "stream-1",
      "cursor" => cursor,
      "params" => %{
        "thread_id" => "thread-1",
        "turn_id" => "turn-1",
        "item_id" => "item-1",
        "delta" => "hello"
      }
    }
  end

  def event do
    %{
      "schema_version" => "1.0",
      "event_id" => "evt-1",
      "delivery_attempt_id" => "delivery-1",
      "created_at" => "2026-10-22T08:00:00Z",
      "correlation_id" => "flow-1",
      "project_ref" => "project-opaque",
      "type" => "github.pull_request",
      "payload" => %{"number" => 1}
    }
  end

  def request(method, params, fields \\ %{}) do
    Map.merge(
      %{
        "schema_version" => "1.0",
        "type" => "request",
        "id" => "req-1",
        "correlation_id" => "flow-1",
        "method" => method,
        "params" => params
      },
      fields
    )
  end
end
