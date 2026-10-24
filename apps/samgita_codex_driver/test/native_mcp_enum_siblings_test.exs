defmodule SamgitaCodexDriver.NativeMcpEnumSiblingsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/mcp_enum_siblings_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @message "Owned enum sibling selection only"
  @meta %{"fixture/request" => %{"marker" => "enum-siblings"}}
  @answer %{
    "plainRoute" => "plain-green-λ",
    "legacyRoute" => "legacy-green-λ",
    "plainRoutes" => ["plain-third", "plain-second-λ"],
    "titledRoutes" => ["titled-third", "titled-second-λ"]
  }
  @reply %{
    "action" => "accept",
    "content" => @answer,
    "_meta" => %{"fixture/response" => %{"selected" => @answer}}
  }
  @effect %{"effect" => "accepted-enum-siblings", "selection" => @answer}

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-mcp-enum-siblings-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
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
    test "native #{profile} enum siblings preserve native schema and explicit raw-value selections",
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

      # The complete native schema is checked before this fixed answer is sent.
      # This proves transport of a legal selection, not arbitrary constraint enforcement.
      for {field, value} <- @answer do
        assert value != schema()["properties"][field]["default"]
      end

      refute @answer["legacyRoute"] in schema()["properties"]["legacyRoute"]["enumNames"]
      titles = Enum.map(schema()["properties"]["titledRoutes"]["items"]["anyOf"], & &1["title"])
      refute Enum.any?(@answer["titledRoutes"], &(&1 in titles))
      assert @answer["plainRoutes"] == ["plain-third", "plain-second-λ"]
      assert @answer["titledRoutes"] == ["titled-third", "titled-second-λ"]
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
                 message["id"] == "synthetic-enum-siblings",
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
        "plainRoute" => %{
          "type" => "string",
          "title" => "Owned plain route λ",
          "description" => "Choose a synthetic raw identifier.",
          "enum" => ["plain-blue", "plain-green-λ"],
          "default" => "plain-blue"
        },
        "legacyRoute" => %{
          "type" => "string",
          "title" => "Owned legacy route λ",
          "description" => "Legacy labels differ from their raw values.",
          "enum" => ["legacy-blue", "legacy-green-λ"],
          "enumNames" => ["Legacy Blue display", "Legacy Green display λ"],
          "default" => "legacy-blue"
        },
        "plainRoutes" => %{
          "type" => "array",
          "title" => "Owned plain routes λ",
          "description" => "Select two raw identifiers in explicit reply order.",
          "minItems" => 1,
          "maxItems" => 2,
          "items" => %{
            "type" => "string",
            "enum" => ["plain-first", "plain-second-λ", "plain-third"]
          },
          "default" => ["plain-first"]
        },
        "titledRoutes" => %{
          "type" => "array",
          "title" => "Owned titled routes λ",
          "description" => "Submit const values, never the display titles.",
          "minItems" => 1,
          "maxItems" => 2,
          "items" => %{
            "anyOf" => [
              %{
                "const" => "titled-first",
                "title" => "First display"
              },
              %{
                "const" => "titled-second-λ",
                "title" => "Second display λ"
              },
              %{
                "const" => "titled-third",
                "title" => "Third display"
              }
            ]
          },
          "default" => ["titled-first"]
        }
      },
      "required" => ["plainRoute", "legacyRoute", "plainRoutes", "titledRoutes"]
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
          flunk("Unexpected native enum sibling event gap")
      after
        remaining -> flunk("Native enum sibling deadline: #{inspect(Session.status(pid))}")
      end
    end
  end

  defp completed?(events, turn),
    do: TurnFixture.notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

  defp journal(fixture) do
    case File.read(Path.join(fixture.codex_home, "mcp-enum-siblings.jsonl")) do
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
