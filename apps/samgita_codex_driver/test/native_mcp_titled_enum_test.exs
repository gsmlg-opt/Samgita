defmodule SamgitaCodexDriver.NativeMcpTitledEnumTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/mcp_titled_enum_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @message "Owned titled enum selection only"
  @meta %{"fixture/request" => %{"marker" => "titled-enum"}}
  @reply %{
    "action" => "accept",
    "content" => %{"route" => "green-id-λ"},
    "_meta" => %{"fixture/response" => %{"selected" => "green-id-λ"}}
  }
  @effect %{"effect" => "accepted-titled-enum", "route" => "green-id-λ"}

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-mcp-titled-enum-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, tags[:profile])
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    %{binary: binary, fixture: fixture, root: root}
  end

  for {profile, protocol} <- [{"legacy", "2025-06-18"}, {"modern", "2026-07-28"}] do
    @protocol protocol
    @tag profile: profile
    test "native #{profile} typed titled enum preserves const/title/default and explicit selection",
         ctx do
      pid = TurnFixture.start(ctx)
      id = TurnFixture.thread(ctx, pid)
      assert ModelFixture.requests(ctx.fixture) == []
      assert effects(ctx.fixture) == []

      turn =
        TurnFixture.start_turn(pid, id, [
          %{"type" => "text", "text" => @message},
          %{"type" => "mention", "name" => "Fixture", "path" => "mcp://fixture"}
        ])

      events = collect(pid, [], &(interactions(&1) != []), true)
      assert [request] = interactions(events)
      assert request.wire["method"] == "mcpServer/elicitation/request"
      assert request.handle.id == request.wire["id"]

      assert request.wire["params"] === %{
               "threadId" => id,
               "turnId" => turn,
               "serverName" => "fixture",
               "mode" => "form",
               "message" => @message,
               "_meta" => @meta,
               "requestedSchema" => schema()
             }

      generation = request.handle.generation
      pending = Map.fetch!(:sys.get_state(pid).interactions, request.handle.id)
      assert pending.handle == request.handle
      assert is_integer(Process.read_timer(pending.timer))

      assert %{
               phase: :ready,
               generation: ^generation,
               pending: 0,
               interactions: 1,
               interaction_outcomes: 0,
               uncertain: 0
             } = Session.status(pid)

      assert Session.interaction_outcomes(pid) == []
      assert length(ModelFixture.requests(ctx.fixture)) == 1
      assert effects(ctx.fixture) == []
      refute completed?(events, turn)
      assert File.ls!(ctx.fixture.workspace) == []

      # The displayed title is not the submitted value; only this fixed synthetic
      # const is explicitly selected, after the complete native schema is checked.
      refute @reply["content"]["route"] in ["Blue display", "Green display λ"]
      assert @reply["content"]["route"] != schema()["properties"]["route"]["default"]
      assert :ok = Session.respond(pid, request.handle, {:ok, @reply})
      assert_stale(pid, request)
      request_id = request.wire["id"]

      events =
        collect(
          pid,
          events,
          fn all ->
            completed?(all, turn) &&
              TurnFixture.notification(
                all,
                "serverRequest/resolved",
                &(&1["requestId"] == request_id)
              )
          end,
          false
        )

      assert [^request] = interactions(events)

      assert %{"threadId" => ^id, "turn" => %{"id" => ^turn, "status" => "completed"}} =
               TurnFixture.notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

      assert %{"threadId" => ^id, "requestId" => ^request_id} =
               TurnFixture.notification(
                 events,
                 "serverRequest/resolved",
                 &(&1["requestId"] == request_id)
               )

      rows = journal(ctx.fixture)
      assert effects(ctx.fixture) == [@effect]
      assert [elicitation] = messages(rows, "out", "elicitation/create")
      assert elicitation["params"]["requestedSchema"] === schema()
      assert elicitation["params"]["_meta"] === @meta

      assert [received] =
               for(
                 %{"direction" => "in", "message" => message} <- rows,
                 message["id"] == "synthetic-titled-enum",
                 do: message
               )

      assert received["result"] === @reply
      refute Map.has_key?(received, "error")
      assert [call] = messages(rows, "in", "tools/call")
      assert %{"name" => "confirm", "arguments" => %{}} = call["params"]
      assert_protocol(rows, @protocol)

      assert [first, second] = ModelFixture.requests(ctx.fixture)
      assert namespace = Enum.find(first["tools"], &(&1["name"] == "mcp__fixture"))
      assert Enum.any?(namespace["tools"], &(&1["name"] == "confirm"))

      assert [output] =
               Enum.filter(
                 second["input"],
                 &(&1["type"] == "function_call_output" and &1["call_id"] == "interaction-call-1")
               )

      assert [%{"type" => "input_text"}, %{"type" => "input_text", "text" => text}] =
               output["output"]

      assert JSON.decode!(text) === received
      item = assert_mcp_items(events, id, turn)

      assert [%{"id" => ^turn, "status" => "completed", "items" => items}] =
               TurnFixture.call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})[
                 "thread"
               ]["turns"]

      assert [persisted] = Enum.filter(items, &(&1["type"] == "mcpToolCall"))

      assert Map.take(persisted, ~w(id server tool arguments status)) ==
               Map.take(item, ~w(id server tool arguments status))

      assert %{
               phase: :ready,
               pending: 0,
               interactions: 0,
               interaction_outcomes: 1,
               uncertain: 0,
               gap: nil
             } = Session.status(pid)

      assert Session.uncertain_operations(pid) == []
      assert [outcome] = Session.interaction_outcomes(pid)
      assert outcome.handle == request.handle and outcome.status == :resolution_observed
      assert_stale(pid, request)
      assert length(ModelFixture.requests(ctx.fixture)) == 2
      assert effects(ctx.fixture) == [@effect]
      assert File.ls!(ctx.fixture.workspace) == []
      refute File.exists?(Path.join(ctx.fixture.codex_home, "rules/default.rules"))
    end
  end

  defp schema do
    %{
      "type" => "object",
      "properties" => %{
        "route" => %{
          "type" => "string",
          "title" => "Owned route λ",
          "description" => "Choose a synthetic identifier, not its display title.",
          "oneOf" => [
            %{"const" => "blue-id", "title" => "Blue display"},
            %{"const" => "green-id-λ", "title" => "Green display λ"}
          ],
          "default" => "blue-id"
        }
      },
      "required" => ["route"]
    }
  end

  defp assert_mcp_items(events, id, turn) do
    [started, completed] =
      for method <- ["item/started", "item/completed"] do
        assert [params] =
                 for(
                   event <- events,
                   event.wire["method"] == method,
                   event.wire["params"]["item"]["type"] == "mcpToolCall",
                   do: event.wire["params"]
                 )

        assert params["threadId"] == id and params["turnId"] == turn
        assert %{"server" => "fixture", "tool" => "confirm", "arguments" => %{}} = params["item"]

        assert params["item"]["status"] ==
                 if(method == "item/started", do: "inProgress", else: "completed")

        params["item"]
      end

    assert started["id"] == completed["id"]
    completed
  end

  defp collect(pid, events, predicate, allow_request, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 15_000
    assert {:ok, incoming} = Session.drain(pid)

    unless allow_request do
      refute Enum.any?(incoming, &(&1.kind == :server_request)),
             "Unexpected native request; never automatically answer unrelated interactions"
    end

    events = events ++ incoming

    if predicate.(events) do
      events
    else
      assert %{phase: :ready} = Session.status(pid)
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:codex_driver, ^pid, :events_available} ->
          collect(pid, events, predicate, allow_request, deadline)

        {:codex_driver, ^pid, {:gap, _}} ->
          flunk("Unexpected native titled enum event gap")
      after
        remaining -> flunk("Native titled enum deadline: #{inspect(Session.status(pid))}")
      end
    end
  end

  defp completed?(events, turn),
    do: TurnFixture.notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

  defp journal(fixture) do
    case File.read(Path.join(fixture.codex_home, "mcp-titled-enum.jsonl")) do
      {:ok, text} -> text |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
      {:error, :enoent} -> []
    end
  end

  defp messages(rows, direction, method) do
    for %{"direction" => ^direction, "message" => message} <- rows,
        message["method"] == method,
        do: message
  end

  defp effects(fixture), do: Enum.filter(journal(fixture), &Map.has_key?(&1, "effect"))
  defp interactions(events), do: Enum.filter(events, &(&1.kind == :server_request))

  defp assert_stale(pid, request) do
    assert {:error, %Error{code: :stale_interaction, uncertain: false}} =
             Session.respond(pid, request.handle, {:ok, @reply})
  end

  defp assert_protocol(rows, "2025-06-18") do
    assert [message] = messages(rows, "in", "initialize")
    assert message["params"]["protocolVersion"] == "2025-06-18"
    assert messages(rows, "in", "server/discover") == []
  end

  defp assert_protocol(rows, "2026-07-28") do
    assert [message] = messages(rows, "in", "server/discover")
    assert message["params"]["_meta"]["io.modelcontextprotocol/protocolVersion"] == "2026-07-28"
    assert messages(rows, "in", "initialize") == []
  end
end
