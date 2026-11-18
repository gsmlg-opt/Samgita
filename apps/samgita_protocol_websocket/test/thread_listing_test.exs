defmodule SamgitaProtocolWebSocket.ThreadListingTest do
  @moduledoc "Functional thread listing through a loopback fake host using a synthetic fixture."
  use ExUnit.Case, async: true
  alias SamgitaProtocolWebSocket.{Client, FakeAgent}

  @capabilities ["sessions.list.v1", "sessions.v1"]

  setup do
    agent = start_supervised!({FakeAgent, token: "thread-list-fixture", owner: self(), port: 0})
    client = connect(agent)
    %{agent: agent, client: client}
  end

  test "a fresh connection lists earlier threads and preserves their read representation", ctx do
    params = %{"title" => "Existing", "metadata" => %{"repository" => "repo-a"}}
    assert {:ok, %{"thread_id" => id}} = request(ctx.client, "thread/start", params)
    :ok = Client.close(ctx.client)
    client = connect(ctx.agent)

    assert {:ok,
            %{"threads" => [%{"thread_id" => ^id, "title" => "Existing"}], "next_cursor" => nil}} =
             request(client, "thread/list", %{})

    assert {:ok, %{"thread_id" => ^id, "thread" => ^params}} =
             request(client, "thread/read", %{"thread_id" => id})
  end

  test "metadata filtering uses an exact subset and pagination has no duplicate or missing rows",
       ctx do
    ids =
      for title <- ["One", "Two", "Three"] do
        assert {:ok, %{"thread_id" => id}} =
                 request(ctx.client, "thread/start", %{
                   "title" => title,
                   "metadata" => %{"repository" => "repo-a", "nested" => %{"branch" => "main"}}
                 })

        id
      end

    assert {:ok, _} =
             request(ctx.client, "thread/start", %{
               "title" => "Another repository",
               "metadata" => %{"repository" => "repo-b"}
             })

    assert {:ok, _} = request(ctx.client, "thread/start", %{"title" => "No metadata"})
    filter = %{"repository" => "repo-a"}

    assert {:ok, %{"threads" => first, "next_cursor" => cursor}} =
             request(ctx.client, "thread/list", %{"metadata" => filter, "limit" => 2})

    assert length(first) == 2
    assert is_binary(cursor)

    assert {:ok, %{"threads" => last, "next_cursor" => nil}} =
             request(ctx.client, "thread/list", %{
               "metadata" => filter,
               "limit" => 2,
               "cursor" => cursor
             })

    assert Enum.map(first ++ last, & &1["thread_id"]) == Enum.sort(ids)

    assert {:ok, %{"threads" => [], "next_cursor" => nil}} =
             request(ctx.client, "thread/list", %{
               "metadata" => %{"nested" => %{"branch" => "other"}}
             })

    assert {:ok, %{"threads" => nested}} =
             request(ctx.client, "thread/list", %{
               "metadata" => %{"nested" => %{"branch" => "main"}}
             })

    assert Enum.map(nested, & &1["thread_id"]) == Enum.sort(ids)
  end

  test "cursors reject malformed values, missing anchors and a changed metadata filter", ctx do
    for repository <- ["repo-a", "repo-a", "repo-b"] do
      assert {:ok, _} =
               request(ctx.client, "thread/start", %{"metadata" => %{"repository" => repository}})
    end

    assert {:ok, %{"next_cursor" => cursor}} =
             request(ctx.client, "thread/list", %{
               "metadata" => %{"repository" => "repo-a"},
               "limit" => 1
             })

    missing =
      cursor
      |> Base.url_decode64!(padding: false)
      |> JSON.decode!()
      |> Map.put("after", "missing-thread")
      |> JSON.encode!()
      |> Base.url_encode64(padding: false)

    for params <- [
          %{"cursor" => "malformed!"},
          %{"cursor" => missing, "metadata" => %{"repository" => "repo-a"}},
          %{"cursor" => cursor},
          %{"cursor" => cursor, "metadata" => %{"repository" => "repo-b"}}
        ] do
      assert {:error, %{code: "invalid_params"}} = request(ctx.client, "thread/list", params)
    end
  end

  test "large metadata filters produce bounded cursors that remain usable", ctx do
    filter = %{"repository" => String.duplicate("r", 50_000)}

    ids =
      for _ <- 1..2 do
        assert {:ok, %{"thread_id" => id}} =
                 request(ctx.client, "thread/start", %{"metadata" => filter})

        id
      end

    assert {:ok, %{"threads" => [first], "next_cursor" => cursor}} =
             request(ctx.client, "thread/list", %{"metadata" => filter, "limit" => 1})

    assert is_binary(cursor) and byte_size(cursor) < 1024

    assert {:ok, %{"threads" => [last], "next_cursor" => nil}} =
             request(ctx.client, "thread/list", %{
               "metadata" => filter,
               "limit" => 1,
               "cursor" => cursor
             })

    assert [first["thread_id"], last["thread_id"]] == Enum.sort(ids)
  end

  test "the fake host defaults to 25 rows and caps an oversized page request at 100", ctx do
    for _ <- 1..101 do
      assert {:ok, _} = request(ctx.client, "thread/start", %{})
    end

    assert {:ok, %{"threads" => default, "next_cursor" => default_cursor}} =
             request(ctx.client, "thread/list", %{})

    assert length(default) == 25
    assert is_binary(default_cursor)

    assert {:ok, %{"threads" => capped, "next_cursor" => cap_cursor}} =
             request(ctx.client, "thread/list", %{"limit" => 1000})

    assert length(capped) == 100

    assert {:ok, %{"threads" => [last], "next_cursor" => nil}} =
             request(ctx.client, "thread/list", %{"limit" => 1000, "cursor" => cap_cursor})

    refute last["thread_id"] in Enum.map(capped, & &1["thread_id"])
  end

  defp connect(agent) do
    assert {:ok, client} =
             Client.connect(FakeAgent.url(agent),
               token: "thread-list-fixture",
               capabilities: @capabilities,
               max_streams: 128
             )

    on_exit(fn -> if Process.alive?(client), do: Client.close(client) end)

    assert {:ok, %{"capabilities" => @capabilities}} =
             request(client, "connection/initialize", %{
               "versions" => ["1.0"],
               "capabilities" => @capabilities,
               "required_capabilities" => ["sessions.list.v1"]
             })

    client
  end

  defp request(client, method, params) do
    id = "thread-list-" <> Integer.to_string(System.unique_integer([:positive]))
    opts = [id: id, correlation_id: id]

    opts =
      if SamgitaProtocol.Schema.mutating?(method),
        do: Keyword.put(opts, :command_id, id),
        else: opts

    Client.request(client, method, params, opts)
  end
end
