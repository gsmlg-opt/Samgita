defmodule SamgitaCodexDriver.NativeAttachmentLifecycleTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  alias SamgitaProtocolCodex.Error
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @missing "00000000-0000-4000-8000-000000000000"

  setup tags do
    ctx = TurnFixture.setup(tags)

    if tags[:in_memory] do
      config = Path.join(ctx.fixture.codex_home, "config.toml")
      store_id = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)

      File.write!(
        config,
        ~s(experimental_thread_store = { type = "in_memory", id = "#{store_id}" }\n) <>
          File.read!(config)
      )
    end

    ctx
  end

  test "attachment identity and arbitrary JSON survive duplicate payloads and a cold read", ctx do
    pid = start(ctx)
    id = materialize(ctx, pid)
    payloads = [nil, [nil, true, 9, "λ🙂"], %{"nested" => %{"future" => [false, nil]}}]

    attachments =
      for {payload, index} <- Enum.with_index(payloads) do
        params = params(id, "type λ", "key #{index}", payload)
        added = call(pid, "thread/attachment/add", params)
        assert added["outcome"] == "created"
        attachment = added["attachment"]
        assert attachment["payload"] == payload
        assert attachment["attachmentType"] == "type λ"
        assert attachment["identityKey"] == "key #{index}"
        assert is_integer(attachment["createdAt"])
        assert attachment["id"] =~ ~r/\A[0-9a-f-]{36}\z/
        assert_change(pid, id, attachment, "created")

        assert call(pid, "thread/attachment/add", %{params | "payload" => "changed"}) == %{
                 "outcome" => "existing",
                 "attachment" => attachment
               }

        attachment
      end

    assert Enum.sort_by(list(pid, id)["data"], & &1["id"]) ==
             Enum.sort_by(attachments, & &1["id"])

    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert call(cold, "thread/loaded/list", %{})["data"] == []

    assert Enum.sort_by(list(cold, id)["data"], & &1["id"]) ==
             Enum.sort_by(attachments, & &1["id"])

    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    assert_ready(cold)
  end

  test "pagination keeps its keyset after anchor deletion and rejects a different thread cursor",
       ctx do
    pid = start(ctx)
    id = materialize(ctx, pid)
    other = materialize(ctx, pid)

    attachments =
      for index <- 1..3 do
        call(pid, "thread/attachment/add", params(id, "document", "key-#{index}", index))[
          "attachment"
        ]
      end

    ordered = Enum.sort_by(attachments, &{&1["createdAt"], &1["id"]})
    first = list(pid, id, %{"limit" => 0, "cursor" => nil})
    assert first["data"] == [hd(ordered)]
    assert is_binary(first["nextCursor"])
    assert list(pid, id, %{"limit" => 1000}) == %{"data" => ordered, "nextCursor" => nil}

    assert upstream_error(pid, "thread/attachment/list", %{
             "threadId" => other,
             "cursor" => first["nextCursor"]
           }) == invalid("invalid pagination cursor")

    assert call(pid, "thread/attachment/remove", removal(id, hd(ordered))) == %{}
    second = list(pid, id, %{"limit" => 1, "cursor" => first["nextCursor"]})
    assert second["data"] == [Enum.at(ordered, 1)]
    final = list(pid, id, %{"limit" => 1, "cursor" => second["nextCursor"]})
    assert final == %{"data" => [List.last(ordered)], "nextCursor" => nil}

    for cursor <- ["invalid-cursor", "#{id}|not-a-time|#{hd(ordered)["id"]}"] do
      assert upstream_error(pid, "thread/attachment/list", %{
               "threadId" => id,
               "cursor" => cursor
             }) == invalid("invalid pagination cursor")
    end

    assert list(pid, @missing) == %{"data" => [], "nextCursor" => nil}
    assert_ready(pid)
  end

  test "owner pagination is bound to exact identity and archived filter across restart", ctx do
    pid = start(ctx)
    ids = for _ <- 1..3, do: materialize(ctx, pid)

    for id <- ids do
      call(pid, "thread/attachment/add", params(id, "document", "shared", %{}))
    end

    unrelated = hd(ids)
    call(pid, "thread/attachment/add", params(unrelated, "other", "shared", %{}))
    call(pid, "thread/attachment/add", params(unrelated, "document", "other", %{}))
    archived = List.last(ids)
    assert call(pid, "thread/archive", %{"threadId" => archived}) == %{}
    expected = Enum.map(Enum.sort(ids), &%{"threadId" => &1, "archived" => &1 == archived})
    assert owners(pid) == %{"data" => expected, "nextCursor" => nil}
    assert owners(pid, %{"archived" => nil}) == owners(pid)

    assert owners(pid, %{"archived" => true}) == %{
             "data" => [%{"threadId" => archived, "archived" => true}],
             "nextCursor" => nil
           }

    assert owners(pid, %{"archived" => false})["data"] ==
             Enum.reject(expected, & &1["archived"])

    first = owners(pid, %{"limit" => 0})
    assert first["data"] == [hd(expected)]
    assert is_binary(first["nextCursor"])

    for changes <- [
          %{"identityKey" => "other"},
          %{"attachmentType" => "other"},
          %{"archived" => false}
        ] do
      error =
        owners_params(%{"cursor" => first["nextCursor"]})
        |> Map.merge(changes)

      assert upstream_error(pid, "thread/attachmentOwner/list", error) ==
               invalid("invalid pagination cursor")
    end

    second = owners(pid, %{"cursor" => first["nextCursor"], "limit" => 1})
    third = owners(pid, %{"cursor" => second["nextCursor"], "limit" => 1})
    assert first["data"] ++ second["data"] ++ third["data"] == expected
    assert third["nextCursor"] == nil
    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert owners(cold) == %{"data" => expected, "nextCursor" => nil}
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert length(ModelFixture.requests(ctx.fixture)) == 3
    assert_ready(cold)
  end

  test "idempotent removal and recreation preserve current membership with exact change identity",
       ctx do
    pid = start(ctx)
    id = materialize(ctx, pid)

    original =
      call(pid, "thread/attachment/add", params(id, "document", "shared", %{}))["attachment"]

    assert_change(pid, id, original, "created")
    assert call(pid, "thread/attachment/remove", removal(id, original)) == %{}
    assert_change(pid, id, original, "deleted")
    assert list(pid, id) == %{"data" => [], "nextCursor" => nil}
    assert owners(pid) == %{"data" => [], "nextCursor" => nil}
    assert call(pid, "thread/attachment/remove", removal(id, original)) == %{}

    added = call(pid, "thread/attachment/add", params(id, "document", "shared", ["new"]))
    assert added["outcome"] == "created"
    replacement = added["attachment"]
    refute replacement["id"] == original["id"]
    assert replacement["payload"] == ["new"]
    assert_change(pid, id, replacement, "created")
    assert list(pid, id)["data"] == [replacement]
    assert owners(pid)["data"] == [%{"threadId" => id, "archived" => false}]

    # This deletes only this case's synthetic upstream thread, not Samgita data.
    assert call(pid, "thread/delete", %{"threadId" => id}) == %{}
    assert list(pid, id) == %{"data" => [], "nextCursor" => nil}
    assert owners(pid) == %{"data" => [], "nextCursor" => nil}

    assert upstream_error(pid, "thread/attachment/remove", removal(id, replacement)) ==
             invalid("thread not found: #{id}")

    assert_ready(pid)
  end

  test "UTF8 identity and serialized payload byte limits reject changes without overwriting",
       ctx do
    pid = start(ctx)
    id = materialize(ctx, pid)
    type = String.duplicate("λ", 128)
    key = String.duplicate("é", 128)
    payload = String.duplicate("x", 65_534)
    assert byte_size(JSON.encode!(payload)) == 65_536
    added = call(pid, "thread/attachment/add", params(id, type, key, payload))
    assert added["attachment"]["payload"] == payload

    cases = [
      {%{"attachmentType" => " \t"}, "attachmentType must not be empty"},
      {%{"identityKey" => " \n"}, "identityKey must not be empty"},
      {%{"attachmentType" => type <> "x"}, "attachmentType must not exceed 256 bytes"},
      {%{"identityKey" => key <> "x"}, "identityKey must not exceed 256 bytes"},
      {%{"payload" => payload <> "x"}, "attachment payload must not exceed 65536 bytes"},
      {%{"payload" => String.duplicate("λ", 32_768)},
       "attachment payload must not exceed 65536 bytes"}
    ]

    for {changes, message} <- cases do
      assert upstream_error(
               pid,
               "thread/attachment/add",
               Map.merge(params(id, type, key, payload), changes)
             ) ==
               invalid(message)

      assert list(pid, id)["data"] == [added["attachment"]]
    end

    trimmed =
      call(pid, "thread/attachment/add", params(id, " type ", " key ", true))["attachment"]

    assert trimmed["attachmentType"] == " type "
    assert trimmed["identityKey"] == " key "
    assert_ready(pid)
  end

  test "capacity counts distinct identities while concurrent duplicate submission retains one value",
       ctx do
    pid = start(ctx)
    id = materialize(ctx, pid)

    submissions =
      for value <- ["first", "second"] do
        Task.async(fn ->
          call(pid, "thread/attachment/add", params(id, "document", "shared", value))
        end)
      end

    results = Enum.map(submissions, &Task.await(&1, 10_000))
    assert Enum.sort(Enum.map(results, & &1["outcome"])) == ["created", "existing"]
    assert Enum.uniq(Enum.map(results, & &1["attachment"])) |> length() == 1
    [retained] = list(pid, id)["data"]
    assert retained["payload"] in ["first", "second"]

    for index <- 2..100 do
      result = call(pid, "thread/attachment/add", params(id, "document", "key-#{index}", index))
      assert result["outcome"] == "created"
    end

    assert length(list(pid, id, %{"limit" => 1000})["data"]) == 100

    assert call(pid, "thread/attachment/add", params(id, "document", "shared", nil)) == %{
             "outcome" => "existing",
             "attachment" => retained
           }

    assert upstream_error(pid, "thread/attachment/add", params(id, "document", "overflow", %{})) ==
             invalid("thread attachment identity count exceeds 100")

    assert call(pid, "thread/attachment/remove", removal(id, retained)) == %{}

    assert call(pid, "thread/attachment/add", params(id, "document", "overflow", %{}))["outcome"] ==
             "created"

    assert length(list(pid, id, %{"limit" => 100})["data"]) == 100
    assert_ready(pid)
  end

  @tag in_memory: true
  test "unsupported in-memory storage explicitly rejects every attachment operation", ctx do
    pid = start(ctx)

    for {method, values} <- [
          {"thread/attachment/add", params(@missing, "document", "shared", %{})},
          {"thread/attachment/list", %{"threadId" => @missing}},
          {"thread/attachment/remove",
           %{"threadId" => @missing, "attachmentType" => "document", "identityKey" => "shared"}},
          {"thread/attachmentOwner/list", owners_params(%{})}
        ] do
      assert upstream_error(pid, method, values) == %{
               "code" => -32_601,
               "message" => "#{method} is not supported by the configured thread store"
             }
    end

    assert ModelFixture.requests(ctx.fixture) == []
    assert_ready(pid)
  end

  test "stable attachment methods work without experimental negotiation and reject malformed inputs",
       ctx do
    pid = start(ctx, experimental: false)
    id = materialize(ctx, pid)
    added = call(pid, "thread/attachment/add", params(id, "document", "shared", false))
    assert_change(pid, id, added["attachment"], "created")
    assert list(pid, id)["data"] == [added["attachment"]]
    assert owners(pid)["data"] == [%{"threadId" => id, "archived" => false}]

    for {method, malformed} <- [
          {"thread/attachment/add",
           Map.delete(params(id, "document", "shared", %{}), "identityKey")},
          {"thread/attachment/list", %{"threadId" => id, "limit" => -1}},
          {"thread/attachmentOwner/list", owners_params(%{"archived" => "false"})},
          {"thread/attachment/remove",
           %{"threadId" => id, "attachmentType" => 1, "identityKey" => "shared"}}
        ] do
      assert {:error, %Error{code: :schema_violation}} = Session.request(pid, method, malformed)
      assert upstream_error(pid, method, malformed, validation: :wire)["code"] == -32_600
      assert list(pid, id)["data"] == [added["attachment"]]
    end

    assert upstream_error(
             pid,
             "thread/attachment/add",
             params(@missing, "document", "shared", nil)
           ) ==
             invalid("thread not found: #{@missing}")

    assert call(pid, "thread/attachment/remove", removal(id, added["attachment"])) == %{}
    assert_change(pid, id, added["attachment"], "deleted")
    assert_ready(pid)
  end

  defp materialize(ctx, pid) do
    id = thread(ctx, pid)
    turn = start_turn(pid, id, [%{"type" => "text", "text" => "Synthetic attachment fixture"}])
    finish_turn(pid, id, turn)
    id
  end

  defp params(id, type, key, payload),
    do: %{"threadId" => id, "attachmentType" => type, "identityKey" => key, "payload" => payload}

  defp removal(id, attachment),
    do: Map.put(Map.take(attachment, ["attachmentType", "identityKey"]), "threadId", id)

  defp list(pid, id, more \\ %{}),
    do: call(pid, "thread/attachment/list", Map.merge(%{"threadId" => id}, more))

  defp owners_params(more),
    do: Map.merge(%{"attachmentType" => "document", "identityKey" => "shared"}, more)

  defp owners(pid, more \\ %{}), do: call(pid, "thread/attachmentOwner/list", owners_params(more))
  defp invalid(message), do: %{"code" => -32_602, "message" => message}

  defp assert_ready(pid),
    do: assert(%{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid))

  defp assert_change(pid, id, attachment, operation) do
    expected = %{
      "threadId" => id,
      "attachmentType" => attachment["attachmentType"],
      "identityKey" => attachment["identityKey"],
      "attachmentId" => attachment["id"],
      "operation" => operation
    }

    collect_change(pid, expected, System.monotonic_time(:millisecond) + 5_000)
  end

  defp collect_change(pid, expected, deadline) do
    assert {:ok, events} = Session.drain(pid)

    if Enum.any?(
         events,
         &(&1.wire["method"] == "thread/attachment/updated" and &1.wire["params"] == expected)
       ) do
      :ok
    else
      remaining = deadline - System.monotonic_time(:millisecond)
      assert remaining > 0, "Missing native attachment change: #{inspect(expected)}"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected attachment event gap")
      after
        min(remaining, 20) -> :ok
      end

      collect_change(pid, expected, deadline)
    end
  end
end
