defmodule SamgitaCodexDriver.NativeMcpUrlElicitationTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/mcp_url_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @meta %{"fixture/request" => %{"kind" => "url-decision"}}

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-mcp-url-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{binary: binary, root: root}
  end

  for {profile, protocol} <- [{"legacy", "2025-06-18"}, {"modern", "2026-07-28"}],
      action <- ["accept", "decline", "cancel"] do
    @profile profile
    @protocol protocol
    @action action
    test "native #{@profile} URL elicitation #{@action} reaches peer without visiting URL",
         context do
      fixture = fixture(context.root, @profile)
      ctx = %{binary: context.binary, fixture: fixture}
      pid = TurnFixture.start(ctx)

      try do
        thread = TurnFixture.thread(ctx, pid, %{"ephemeral" => true})
        assert ModelFixture.requests(fixture) == []
        assert trap_requests(fixture) == []

        turn =
          TurnFixture.start_turn(pid, thread, [
            %{"type" => "text", "text" => "Record the synthetic URL decision only"},
            %{"type" => "mention", "name" => "Fixture", "path" => "mcp://fixture"}
          ])

        {request, events} = pending(pid, turn, [], now() + 15_000)
        url = fixture.url <> "/url-trap/owned-synthetic-url"
        assert request.handle.id == request.wire["id"]

        assert request.wire["params"] === %{
                 "threadId" => thread,
                 "turnId" => turn,
                 "serverName" => "fixture",
                 "mode" => "url",
                 "message" => "Record a synthetic URL decision without opening it",
                 "_meta" => @meta,
                 "url" => url,
                 "elicitationId" => "owned-synthetic-url"
               }

        events = hold(pid, fixture, turn, events, now() + 150)
        assert decisions(fixture) == []

        assert :ok =
                 Session.respond(
                   pid,
                   request.handle,
                   {:ok, %{"action" => @action, "content" => nil}}
                 )

        events = finish(pid, turn, events, now() + 15_000)

        assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
                 TurnFixture.notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

        assert [^request] = Enum.filter(events, &(&1.kind == :server_request))
        assert Session.status(pid).interactions == 0
        rows = journal(fixture)
        [elicitation] = messages(rows, "out", "elicitation/create")

        assert elicitation["params"] === %{
                 "mode" => "url",
                 "message" => "Record a synthetic URL decision without opening it",
                 "_meta" => @meta,
                 "url" => url,
                 "elicitationId" => "owned-synthetic-url"
               }

        [received] =
          for %{"direction" => "in", "message" => message} <- rows,
              message["id"] == "synthetic-url-request",
              do: message

        # Pinned core resolve_elicitation supplies {} for accepted absent content;
        # decline/cancel discard content before either MCP encoder runs.
        expected =
          if @action == "accept",
            do: %{"action" => "accept", "content" => %{}},
            else: %{"action" => @action}

        assert received["result"] === expected
        refute Map.has_key?(received, "error")
        [call] = messages(rows, "in", "tools/call")
        assert %{"name" => "confirm", "arguments" => %{}} = call["params"]
        assert_protocol(rows, @protocol)
        assert decisions(fixture) == [%{"decision_observed" => @action}]

        [first, last] = ModelFixture.requests(fixture)
        namespace = Enum.find(first["tools"], &(&1["name"] == "mcp__fixture"))
        assert namespace
        assert Enum.any?(namespace["tools"], &(&1["name"] == "confirm"))

        [output] =
          Enum.filter(
            last["input"],
            &(&1["type"] == "function_call_output" and &1["call_id"] == "interaction-call-1")
          )

        assert [%{"type" => "input_text"}, %{"type" => "input_text", "text" => text}] =
                 output["output"]

        assert JSON.decode!(text) === received

        for method <- ["item/started", "item/completed"] do
          params =
            TurnFixture.notification(events, method, fn params ->
              params["threadId"] == thread and params["turnId"] == turn and
                params["item"]["type"] == "mcpToolCall"
            end)

          assert params

          assert %{"server" => "fixture", "tool" => "confirm", "arguments" => %{}} =
                   params["item"]

          assert params["item"]["status"] ==
                   if(method == "item/started", do: "inProgress", else: "completed")
        end

        refute Enum.any?(events, fn event ->
                 get_in(event, [:wire, "params", "item", "type"]) in [
                   "commandExecution",
                   "webSearch"
                 ]
               end)

        assert {:error, %Error{code: :stale_interaction}} =
                 Session.respond(pid, request.handle, {:ok, %{"action" => @action}})

        assert length(ModelFixture.requests(fixture)) == 2
        assert decisions(fixture) == [%{"decision_observed" => @action}]
        assert trap_requests(fixture) == []
        assert File.ls!(fixture.workspace) == []
        assert :ok = Session.close(pid)
        assert trap_requests(fixture) == []
      after
        if Process.alive?(pid), do: assert(:ok = Session.close(pid))
      end

      assert :ok = ModelFixture.close(fixture)
    end
  end

  defp fixture(root, profile) do
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    try do
      fixture = ModelFixture.start(root, profile)
      File.write!(fixture.requests, "[]")
      on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
      fixture
    after
      if previous,
        do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
        else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
    end
  end

  defp pending(pid, turn, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming

    case Enum.filter(events, &(&1.kind == :server_request)) do
      [event] ->
        assert event.wire["method"] == "mcpServer/elicitation/request"
        {event, events}

      [] ->
        refute TurnFixture.notification(events, "turn/completed", &(&1["turn"]["id"] == turn))
        continue(pid, deadline)
        pending(pid, turn, events, deadline)

      other ->
        flunk("Unexpected native URL requests: #{inspect(other)}")
    end
  end

  defp hold(pid, fixture, turn, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(Enum.filter(events, &(&1.kind == :server_request))) == 1
    assert Session.status(pid).interactions == 1
    assert length(ModelFixture.requests(fixture)) == 1
    assert decisions(fixture) == []
    assert trap_requests(fixture) == []
    refute TurnFixture.notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    if now() >= deadline do
      events
    else
      continue(pid, deadline + 1_000)
      hold(pid, fixture, turn, events, deadline)
    end
  end

  defp finish(pid, turn, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming

    if TurnFixture.notification(events, "turn/completed", &(&1["turn"]["id"] == turn)) do
      events
    else
      continue(pid, deadline)
      finish(pid, turn, events, deadline)
    end
  end

  defp continue(pid, deadline) do
    assert now() < deadline, "Native URL elicitation deadline"
    assert Session.status(pid).phase == :ready

    receive do
      {:codex_driver, ^pid, :events_available} -> :ok
    after
      10 -> :ok
    end
  end

  defp journal(fixture) do
    case File.read(Path.join(fixture.codex_home, "mcp-url.jsonl")) do
      {:ok, text} -> text |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
      {:error, :enoent} -> []
    end
  end

  defp messages(rows, direction, method) do
    for %{"direction" => ^direction, "message" => message} <- rows,
        message["method"] == method,
        do: message
  end

  defp decisions(fixture),
    do: Enum.filter(journal(fixture), &Map.has_key?(&1, "decision_observed"))

  defp trap_requests(fixture),
    do: fixture.codex_home |> Path.join("url-trap.json") |> File.read!() |> JSON.decode!()

  defp assert_protocol(rows, "2025-06-18") do
    [message] = messages(rows, "in", "initialize")
    assert message["params"]["protocolVersion"] == "2025-06-18"
    assert messages(rows, "in", "server/discover") == []
  end

  defp assert_protocol(rows, "2026-07-28") do
    [message] = messages(rows, "in", "server/discover")
    assert message["params"]["_meta"]["io.modelcontextprotocol/protocolVersion"] == "2026-07-28"
    assert messages(rows, "in", "initialize") == []
  end

  defp now, do: System.monotonic_time(:millisecond)
end
