defmodule SamgitaCodexDriver.NativeMcpOpenaiFormsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/mcp_openai_forms_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @message "Owned arbitrary form decision only"
  @meta %{"fixture/request" => %{"kind" => "arbitrary-form", "nested" => [true, nil, "λ"]}}
  @extensions %{"openai/form" => %{}, "openai/elicitation" => %{"form" => %{}}}
  @selection %{
    "template" => "owned-review-λ",
    "settings" => %{"labels" => ["first", "λ"], "threshold" => 0.625}
  }

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-mcp-openai-forms-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    %{binary: binary, root: root}
  end

  for {profile, protocol} <- [{"legacy", "2025-06-18"}, {"modern", "2026-07-28"}],
      {producer, method, mode} <- [
        {"legacy", "openai/form", "openai/form"},
        {"successor", "openai/elicitation/create", "openaiForm"}
      ],
      action <- ["accept", "decline", "cancel"] do
    @profile profile
    @protocol protocol
    @producer producer
    @method method
    @mode mode
    @action action

    test "native #{@profile} #{@mode} arbitrary schema #{@action} resolves once", context do
      fixture = fixture(context.root, @profile <> ":" <> @producer <> ":" <> @action)
      ctx = %{binary: context.binary, fixture: fixture}
      pid = start(ctx)
      thread = TurnFixture.thread(ctx, pid)
      assert ModelFixture.requests(fixture) == []
      assert decisions(fixture) == []
      assert effects(fixture) == []

      turn =
        TurnFixture.start_turn(pid, thread, [
          %{"type" => "text", "text" => @message},
          %{"type" => "mention", "name" => "Fixture", "path" => "mcp://fixture"}
        ])

      events = collect(pid, [], &(interactions(&1) != []), true)
      assert [request] = interactions(events)
      assert request.wire["method"] == "mcpServer/elicitation/request"
      assert request.handle.id == request.wire["id"]

      assert request.wire === %{
               "id" => request.handle.id,
               "method" => "mcpServer/elicitation/request",
               "params" => %{
                 "threadId" => thread,
                 "turnId" => turn,
                 "serverName" => "fixture",
                 "mode" => @mode,
                 "message" => @message,
                 "_meta" => @meta,
                 "requestedSchema" => schema()
               }
             }

      # Observe a held real request throughout a bounded interval. A connected
      # socket alone cannot stand in for pending ownership or absent effects.
      pending = Map.fetch!(:sys.get_state(pid).interactions, request.handle.id)
      events = hold(pid, fixture, request, turn, events, now() + 150)
      assert pending.handle == request.handle
      assert is_integer(Process.read_timer(pending.timer))
      assert Session.interaction_outcomes(pid) == []
      assert Session.uncertain_operations(pid) == []

      assert :ok = Session.respond(pid, request.handle, {:ok, reply(@action)})
      assert Process.read_timer(pending.timer) == false
      assert_stale(pid, request, @action)
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

      assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
               TurnFixture.notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

      assert [%{"threadId" => ^thread, "requestId" => ^request_id}] =
               for(
                 event <- events,
                 event.wire["method"] == "serverRequest/resolved",
                 event.wire["params"]["requestId"] == request_id,
                 do: event.wire["params"]
               )

      rows = journal(fixture)
      assert_protocol(rows, @protocol)
      assert [elicitation] = messages(rows, "out", @method)
      params = %{"message" => @message, "_meta" => @meta, "requestedSchema" => schema()}

      expected_params =
        if @producer == "successor", do: Map.put(params, "mode", "form"), else: params

      assert elicitation["params"] === expected_params

      assert [received] =
               for(
                 %{"direction" => "in", "message" => message} <- rows,
                 message["id"] == "synthetic-arbitrary-form",
                 do: message
               )

      assert received === %{
               "jsonrpc" => "2.0",
               "id" => "synthetic-arbitrary-form",
               "result" => peer_reply(@action)
             }

      assert decisions(fixture) == [%{"decision_observed" => @action}]
      assert effects(fixture) == expected_effects(@action)
      assert [call] = messages(rows, "in", "tools/call")
      assert %{"name" => "confirm", "arguments" => %{}} = call["params"]

      # The peer result is independently fixed before comparing it to the
      # provider continuation; equality between two uninterpreted outputs is
      # insufficient. Exactly two model calls excludes hidden execution loops.
      assert [first, second] = ModelFixture.requests(fixture)
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
      item = assert_items(events, thread, turn)

      assert [%{"id" => ^turn, "status" => "completed", "items" => items}] =
               TurnFixture.call(pid, "thread/read", %{
                 "threadId" => thread,
                 "includeTurns" => true
               })[
                 "thread"
               ]["turns"]

      assert [persisted] = Enum.filter(items, &(&1["type"] == "mcpToolCall"))

      assert Map.take(persisted, ~w(id server tool arguments status)) ==
               Map.take(item, ~w(id server tool arguments status))

      assert [%{"text" => "Deterministic local fixture answer"}] =
               Enum.filter(items, &(&1["type"] == "agentMessage"))
               |> Enum.map(&Map.take(&1, ["text"]))

      assert %{
               phase: :ready,
               pending: 0,
               interactions: 0,
               interaction_outcomes: 1,
               uncertain: 0,
               gap: nil
             } = Session.status(pid)

      assert [outcome] = Session.interaction_outcomes(pid)
      assert outcome.handle == request.handle and outcome.status == :resolution_observed
      assert Session.uncertain_operations(pid) == []
      assert_stale(pid, request, @action)
      assert length(ModelFixture.requests(fixture)) == 2
      assert effects(fixture) == expected_effects(@action)
      assert decisions(fixture) == [%{"decision_observed" => @action}]
      assert File.ls!(fixture.workspace) == []
      refute File.exists?(Path.join(fixture.codex_home, "rules/default.rules"))
    end
  end

  defp start(context) do
    fixture = context.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: context.binary,
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
             cwd: fixture.workspace,
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_openai_forms_fixture", "version" => "0.1.0"},
               %{"experimentalApi" => true, "extensions" => @extensions}
             )

    pid
  end

  defp fixture(root, profile) do
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    try do
      fixture = ModelFixture.start(root, profile)
      on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
      fixture
    after
      if previous,
        do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
        else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
    end
  end

  defp schema do
    %{
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "type" => "object",
      "properties" => %{
        "template" => %{
          "type" => "openai/imagePicker",
          "items" => [
            %{
              "id" => "owned-review-λ",
              "title" => "Owned review λ",
              "image" => "data:image/svg+xml;base64,PHN2Zy8+"
            }
          ]
        },
        "settings" => %{
          "type" => "object",
          "properties" => %{
            "labels" => %{"type" => "array", "items" => %{"type" => "string"}},
            "threshold" => %{"type" => ["number", "null"]}
          },
          "required" => ["labels"],
          "additionalProperties" => false
        }
      },
      "required" => ["template", "settings"],
      "additionalProperties" => false
    }
  end

  defp reply(action) do
    %{
      "action" => action,
      "content" => if(action == "accept", do: @selection, else: nil),
      "_meta" => %{"fixture/response" => %{"decision" => action, "marker" => "owned-λ"}}
    }
  end

  defp peer_reply("accept"), do: reply("accept")
  defp peer_reply(action), do: Map.delete(reply(action), "content")

  defp expected_effects("accept"),
    do: [%{"effect" => "accepted-arbitrary-form", "selection" => @selection}]

  defp expected_effects(_), do: []

  defp hold(pid, fixture, request, turn, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert [^request] = interactions(events)
    pending = Map.fetch!(:sys.get_state(pid).interactions, request.handle.id)
    assert pending.handle == request.handle
    assert is_integer(Process.read_timer(pending.timer))

    assert %{
             phase: :ready,
             generation: generation,
             pending: 0,
             interactions: 1,
             interaction_outcomes: 0,
             uncertain: 0,
             gap: nil
           } = Session.status(pid)

    assert generation == request.handle.generation
    assert length(ModelFixture.requests(fixture)) == 1
    assert decisions(fixture) == []
    assert effects(fixture) == []
    refute completed?(events, turn)
    assert File.ls!(fixture.workspace) == []

    remaining = deadline - now()

    if remaining <= 0 do
      events
    else
      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native arbitrary-form event gap")
      after
        min(remaining, 10) -> :ok
      end

      hold(pid, fixture, request, turn, events, deadline)
    end
  end

  defp assert_items(events, thread, turn) do
    [started, completed] =
      for method <- ["item/started", "item/completed"] do
        assert [params] =
                 for(
                   event <- events,
                   event.wire["method"] == method,
                   event.wire["params"]["item"]["type"] == "mcpToolCall",
                   do: event.wire["params"]
                 )

        assert params["threadId"] == thread and params["turnId"] == turn
        assert %{"server" => "fixture", "tool" => "confirm", "arguments" => %{}} = params["item"]

        assert params["item"]["status"] ==
                 if(method == "item/started", do: "inProgress", else: "completed")

        params["item"]
      end

    assert started["id"] == completed["id"]

    refute Enum.any?(events, fn event ->
             get_in(event, [:wire, "params", "item", "type"]) in [
               "commandExecution",
               "fileChange",
               "webSearch"
             ]
           end)

    completed
  end

  defp collect(pid, events, predicate, allow_request, deadline \\ nil) do
    deadline = deadline || now() + 15_000
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
      remaining = max(deadline - now(), 0)

      receive do
        {:codex_driver, ^pid, :events_available} ->
          collect(pid, events, predicate, allow_request, deadline)

        {:codex_driver, ^pid, {:gap, _}} ->
          flunk("Unexpected native arbitrary-form event gap")
      after
        remaining -> flunk("Native arbitrary-form deadline: #{inspect(Session.status(pid))}")
      end
    end
  end

  defp assert_protocol(rows, "2025-06-18") do
    assert [message] = messages(rows, "in", "initialize")
    assert message["params"]["protocolVersion"] == "2025-06-18"
    assert message["params"]["capabilities"]["extensions"] === @extensions
    assert messages(rows, "in", "server/discover") == []
  end

  defp assert_protocol(rows, "2026-07-28") do
    assert [message] = messages(rows, "in", "server/discover")
    meta = message["params"]["_meta"]
    assert meta["io.modelcontextprotocol/protocolVersion"] == "2026-07-28"
    assert meta["io.modelcontextprotocol/clientCapabilities"]["extensions"] === @extensions
    assert messages(rows, "in", "initialize") == []
  end

  defp journal(fixture) do
    case File.read(Path.join(fixture.codex_home, "mcp-openai-forms.jsonl")) do
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

  defp effects(fixture), do: Enum.filter(journal(fixture), &Map.has_key?(&1, "effect"))
  defp interactions(events), do: Enum.filter(events, &(&1.kind == :server_request))

  defp assert_stale(pid, request, action) do
    assert {:error, %Error{code: :stale_interaction, uncertain: false}} =
             Session.respond(pid, request.handle, {:ok, reply(action)})
  end

  defp completed?(events, turn),
    do: TurnFixture.notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

  defp now, do: System.monotonic_time(:millisecond)
end
