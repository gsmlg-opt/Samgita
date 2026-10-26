defmodule SamgitaCodexDriver.NativeDynamicToolExposureTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error
  import SamgitaCodexDriver.TurnFixture, only: [call: 3, configure_model: 2, notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/dynamic_tool_exposure_fixture.py", __DIR__)
  @name "quasar_lookup_824"
  @description "quasar_lookup_824 retrieves the owned synthetic record λ"
  @namespace "owned_catalog"
  @namespace_description "Owned canonical catalog description β"
  @legacy_namespace_description "Tools in the owned_catalog namespace."
  @read_notice "Full-history hydration is deprecated for paginated threads; omit `includeTurns` or set it to `false`, then page with `thread/turns/list` and `thread/items/list`."
  @arguments %{
    "key" => "owned exposure λ",
    "count" => 7,
    "nested" => %{"enabled" => true, "labels" => ["α", "β"]}
  }
  @schema %{
    "type" => "object",
    "properties" => %{
      "key" => %{"type" => "string"},
      "count" => %{"type" => "integer"},
      "nested" => %{
        "type" => "object",
        "properties" => %{
          "enabled" => %{"type" => "boolean"},
          "labels" => %{"type" => "array", "items" => %{"type" => "string"}}
        },
        "required" => ["enabled", "labels"],
        "additionalProperties" => false
      }
    },
    "required" => ["key", "count", "nested"],
    "additionalProperties" => false
  }
  @content [%{"type" => "inputText", "text" => "Owned synthetic record result λ"}]

  setup tags do
    binary = System.get_env("CODEX_BINARY")
    assert is_binary(binary) and File.regular?(binary)
    assert hash(File.read!(binary)) == @binary_sha

    root =
      Path.join(System.tmp_dir!(), "owned-dynamic-exposure-#{System.unique_integer([:positive])}")

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, tags.scenario)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn ->
      monitor = Process.monitor(fixture.transport.owner.pid)
      assert :ok = ModelFixture.close(fixture)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
      assert :atomics.get(fixture.transport.owner.completion, 1) == 1
      assert Port.info(fixture.port) == nil
    end)

    File.write!(fixture.requests, "[]")
    ctx = %{binary: binary, fixture: fixture, root: root, scenario: tags.scenario}
    configure_model(ctx, %{"supports_search_tool" => true})
    ctx
  end

  for scenario <- ["top_direct", "namespace_direct", "namespace_deferred"] do
    @tag scenario: scenario
    test "canonical dynamic declaration #{scenario} reaches client and cold history", ctx do
      qualify(ctx)
    end
  end

  @tag scenario: "namespace_direct"
  test "legacy null exposure flags select direct native tools and canonical cold history", ctx do
    qualify(ctx, %{"exposeToContext" => nil, "deferLoading" => nil})
  end

  @tag scenario: "namespace_deferred"
  test "legacy hidden exposure with absent deferral selects native discovery and canonical cold history",
       ctx do
    qualify(ctx, %{"exposeToContext" => false})
  end

  @tag scenario: "namespace_direct"
  test "legacy explicit false deferral overrides hidden exposure in native tools and cold history",
       ctx do
    qualify(ctx, %{"exposeToContext" => false, "deferLoading" => false})
  end

  @tag scenario: "top_deferred"
  test "canonical top-level deferred declaration is rejected without creating work or history",
       ctx do
    pid = start_native(ctx)
    native = native_id(pid)
    assert_no_history(ctx, pid)
    assert_deferred_rejection(ctx, pid)
    assert_no_history(ctx, pid)
    assert_idle(pid)
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")

    cold = start_native(ctx)
    cold_native = native_id(cold)
    assert cold_native != native
    assert_no_history(ctx, cold)
    assert_deferred_rejection(ctx, cold)
    assert_no_history(ctx, cold)
    assert_idle(cold)
    assert :ok = Session.close(cold)
    refute File.exists?("/proc/#{cold_native}")
  end

  defp assert_deferred_rejection(ctx, pid) do
    request_id = "owned-top-deferred-start"

    assert {:error, %Error{code: :upstream_error, uncertain: false, wire: wire}} =
             Session.request(
               pid,
               "thread/start",
               %{
                 "model" => "mock-model",
                 "modelProvider" => "fixture",
                 "cwd" => ctx.fixture.workspace,
                 "historyMode" => "paginated",
                 "ephemeral" => false,
                 "dynamicTools" => [declaration(false, true)]
               },
               id: request_id
             )

    assert wire == %{
             "id" => request_id,
             "error" => %{
               "code" => -32_600,
               "message" => "deferred dynamic tool must include a namespace: quasar_lookup_824"
             }
           }
  end

  defp assert_no_history(ctx, pid) do
    assert call(pid, "thread/loaded/list", %{})["data"] == []
    assert call(pid, "thread/list", %{"limit" => 10, "archived" => false})["data"] == []
    assert call(pid, "thread/list", %{"limit" => 10, "archived" => true})["data"] == []
    assert Path.wildcard(Path.join(ctx.fixture.codex_home, "sessions/**/*.jsonl")) == []
    assert ModelFixture.requests(ctx.fixture) == []
    assert File.ls!(ctx.fixture.workspace) == []
  end

  defp qualify(ctx, legacy_flags \\ nil) do
    namespaced = String.starts_with?(ctx.scenario, "namespace")
    deferred = String.ends_with?(ctx.scenario, "deferred")
    namespace = if namespaced, do: @namespace, else: nil

    {declared, namespace_description, format} =
      declaration_input(namespaced, deferred, legacy_flags)

    pid = start_native(ctx)
    native = native_id(pid)

    started =
      call(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "historyMode" => "paginated",
        "ephemeral" => false,
        "dynamicTools" => [declared]
      })

    thread = started["thread"]["id"]
    assert ModelFixture.requests(ctx.fixture) == []
    input = "Owned #{format} declaration #{ctx.scenario} λ"
    host_started_at = System.monotonic_time(:millisecond)

    turn =
      call(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => input}]
      })["turn"]["id"]

    {tool, events} = await_tool(pid, [], System.monotonic_time(:millisecond) + 15_000)
    assert tool.wire["method"] == "item/tool/call"
    assert tool.handle.id == tool.wire["id"]
    assert tool.handle.generation == Session.status(pid).generation

    assert tool.wire["params"] == %{
             "threadId" => thread,
             "turnId" => turn,
             "callId" => "owned-exposure-call",
             "namespace" => namespace,
             "tool" => @name,
             "arguments" => @arguments
           }

    assert :ok =
             Session.respond(
               pid,
               tool.handle,
               {:ok, %{"success" => true, "contentItems" => @content}}
             )

    events = await_turn(pid, turn, events, System.monotonic_time(:millisecond) + 20_000)
    host_finished_at = System.monotonic_time(:millisecond)

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    assert [^tool] = Enum.filter(events, &(&1.kind == :server_request))
    refute Enum.any?(events, &(&1.wire["method"] in ["error", "warning"]))
    completed = item_event(events, "item/completed", "dynamicToolCall")
    duration = completed["item"]["durationMs"]
    assert is_integer(duration) and duration >= 0
    assert duration <= host_finished_at - host_started_at

    expected_item = %{
      "type" => "dynamicToolCall",
      "id" => "owned-exposure-call",
      "namespace" => namespace,
      "tool" => @name,
      "arguments" => @arguments,
      "status" => "completed",
      "contentItems" => @content,
      "success" => true,
      "durationMs" => duration
    }

    assert completed["item"] == expected_item
    began = item_event(events, "item/started", "dynamicToolCall")

    assert began["item"] ==
             Map.merge(expected_item, %{
               "status" => "inProgress",
               "contentItems" => nil,
               "success" => nil,
               "durationMs" => nil
             })

    assert began["threadId"] == thread and began["turnId"] == turn
    assert completed["threadId"] == thread and completed["turnId"] == turn
    assert is_integer(began["startedAtMs"]) and began["startedAtMs"] > 0
    assert completed["completedAtMs"] >= began["startedAtMs"]

    assert item_event(events, "item/completed", "agentMessage")["item"]["text"] ==
             "Owned exposure completed λ"

    requests = ModelFixture.requests(ctx.fixture)
    assert_provider(requests, namespaced, deferred, namespace_description)
    hydrated = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})
    assert_read_notice(pid)

    assert [%{"id" => ^turn, "status" => "completed", "items" => items}] =
             hydrated["thread"]["turns"]

    assert Enum.find(items, &(&1["type"] == "dynamicToolCall")) == expected_item
    assert Enum.map(items, & &1["type"]) == ["userMessage", "dynamicToolCall", "agentMessage"]

    expected_entry = %{
      "turnId" => turn,
      "item" => expected_item,
      "startedAtMs" => began["startedAtMs"],
      "completedAtMs" => completed["completedAtMs"]
    }

    query = %{"threadId" => thread, "turnId" => turn, "itemIds" => ["owned-exposure-call"]}
    assert call(pid, "thread/items/read", query) == %{"data" => [expected_entry]}
    path = hydrated["thread"]["path"]
    snapshot = File.read!(path)
    assert_rollout(snapshot, deferred, namespaced, namespace_description)
    if is_map(legacy_flags), do: assert_legacy_metadata(snapshot, deferred)
    assert_idle(pid)
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")

    cold = start_native(ctx)
    cold_native = native_id(cold)
    assert cold_native != native
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert call(cold, "thread/items/read", query) == %{"data" => [expected_entry]}
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert File.read!(path) == snapshot
    assert ModelFixture.requests(ctx.fixture) == requests
    assert_idle(cold)
    assert :ok = Session.close(cold)
    refute File.exists?("/proc/#{cold_native}")
    assert File.ls!(ctx.fixture.workspace) == []
  end

  defp declaration(namespaced, deferred) do
    function = %{
      "type" => "function",
      "name" => @name,
      "description" => @description,
      "inputSchema" => @schema,
      "deferLoading" => deferred
    }

    if namespaced,
      do: %{
        "type" => "namespace",
        "name" => @namespace,
        "description" => @namespace_description,
        "tools" => [function]
      },
      else: function
  end

  defp declaration_input(_namespaced, _deferred, flags) when is_map(flags) do
    declared =
      Map.merge(
        %{
          "namespace" => @namespace,
          "name" => @name,
          "description" => @description,
          "inputSchema" => @schema
        },
        flags
      )

    {declared, @legacy_namespace_description, "legacy"}
  end

  defp declaration_input(namespaced, deferred, nil),
    do: {declaration(namespaced, deferred), @namespace_description, "canonical"}

  defp provider_function(deferred) do
    spec = %{
      "type" => "function",
      "name" => @name,
      "description" => @description,
      "strict" => false,
      "parameters" => @schema
    }

    if deferred, do: Map.put(spec, "defer_loading", true), else: spec
  end

  defp provider_namespace(namespaced, deferred, namespace_description) do
    %{
      "type" => "namespace",
      "name" => if(namespaced, do: @namespace, else: "functions"),
      "description" => if(namespaced, do: namespace_description, else: ""),
      "tools" => [provider_function(deferred)]
    }
  end

  defp assert_provider(requests, namespaced, deferred, namespace_description) do
    assert length(requests) == if(deferred, do: 3, else: 2)
    assert Enum.all?(requests, &(&1["model"] == "mock-model"))
    initial = hd(requests)

    dynamic =
      Enum.filter(initial["tools"], fn spec ->
        spec["name"] in [@name, @namespace] or
          Enum.any?(Map.get(spec, "tools", []), &(&1["name"] == @name))
      end)

    if deferred do
      assert dynamic == []
      assert Enum.any?(initial["tools"], &(&1["type"] == "tool_search"))
      [search] = Enum.filter(Enum.at(requests, 1)["input"], &(&1["type"] == "tool_search_output"))

      assert Map.take(search, ~w(type call_id status execution tools)) == %{
               "type" => "tool_search_output",
               "call_id" => "owned-exposure-search",
               "status" => "completed",
               "execution" => "client",
               "tools" => [provider_namespace(namespaced, true, namespace_description)]
             }
    else
      expected =
        if namespaced,
          do: provider_namespace(true, false, namespace_description),
          else: provider_function(false)

      assert dynamic == [expected]
      refute Enum.any?(initial["input"], &(&1["type"] == "tool_search_output"))
    end

    [output] = Enum.filter(List.last(requests)["input"], &(&1["type"] == "function_call_output"))
    assert output["call_id"] == "owned-exposure-call"
    assert output["output"] == "Owned synthetic record result λ"
  end

  defp assert_rollout(snapshot, deferred, namespaced, namespace_description) do
    rows = snapshot |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
    response_items = for %{"type" => "response_item", "payload" => item} <- rows, do: item
    [tool] = Enum.filter(response_items, &(&1["type"] == "function_call"))
    assert tool["call_id"] == "owned-exposure-call"
    assert tool["name"] == @name
    assert JSON.decode!(tool["arguments"]) == @arguments
    assert Map.get(tool, "namespace") == if(namespaced, do: @namespace, else: nil)
    [output] = Enum.filter(response_items, &(&1["type"] == "function_call_output"))
    assert output["call_id"] == "owned-exposure-call"

    if deferred do
      [search] = Enum.filter(response_items, &(&1["type"] == "tool_search_output"))
      assert search["call_id"] == "owned-exposure-search"
      assert search["tools"] == [provider_namespace(namespaced, true, namespace_description)]
    else
      refute Enum.any?(response_items, &(&1["type"] == "tool_search_output"))
    end
  end

  defp assert_legacy_metadata(snapshot, deferred) do
    rows = snapshot |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)

    assert [metadata] =
             for(%{"type" => "session_meta", "payload" => metadata} <- rows, do: metadata)

    function = %{
      "type" => "function",
      "name" => @name,
      "description" => @description,
      "inputSchema" => @schema
    }

    function = if deferred, do: Map.put(function, "deferLoading", true), else: function

    assert metadata["dynamic_tools"] == [
             %{
               "type" => "namespace",
               "name" => @namespace,
               "description" => "",
               "tools" => [function]
             }
           ]
  end

  defp item_event(events, method, type) do
    assert [params] =
             for(
               event <- events,
               event.wire["method"] == method,
               get_in(event.wire, ["params", "item", "type"]) == type,
               do: event.wire["params"]
             )

    params
  end

  defp await_tool(pid, events, deadline) do
    assert {:ok, next} = Session.drain(pid)
    events = events ++ next
    assert_collection(pid, events)

    case Enum.filter(events, &(&1.kind == :server_request)) do
      [tool] ->
        {tool, events}

      [] ->
        assert System.monotonic_time(:millisecond) < deadline, "Native dynamic-tool deadline"
        wait_events(pid)
        await_tool(pid, events, deadline)

      _ ->
        flunk("Additional native tool request")
    end
  end

  defp await_turn(pid, turn, events, deadline) do
    assert {:ok, next} = Session.drain(pid)
    events = events ++ next
    assert_collection(pid, events)

    if notification(events, "turn/completed", &(&1["turn"]["id"] == turn)) do
      events
    else
      assert System.monotonic_time(:millisecond) < deadline,
             "Native dynamic-tool completion deadline"

      wait_events(pid)
      await_turn(pid, turn, events, deadline)
    end
  end

  defp assert_collection(pid, events) do
    assert %{phase: :ready, gap: nil} = Session.status(pid)
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
  end

  defp assert_read_notice(pid) do
    # Pinned thread_read awaits this notification before returning its response.
    # The completed request is therefore an explicit notification-order barrier.
    assert {:ok, [notice]} = Session.drain(pid)
    assert_collection(pid, [notice])
    assert notice.kind == :notification
    assert notice.generation == Session.status(pid).generation
    emitted = notice.wire["emittedAtMs"]
    assert is_integer(emitted) and emitted > 0

    assert notice.wire == %{
             "method" => "deprecationNotice",
             "emittedAtMs" => emitted,
             "params" => %{"summary" => @read_notice, "details" => nil}
           }
  end

  defp wait_events(pid) do
    receive do
      {:codex_driver, ^pid, :events_available} -> :ok
      {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native event gap")
    after
      20 -> :ok
    end
  end

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert {:ok, []} = Session.drain(pid)
  end

  defp native_id(pid) do
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    native
  end

  defp start_native(ctx) do
    f = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: ctx.binary,
             args:
               NativeLaunchFixture.ordinary_args([
                 "-c",
                 ~s(approval_policy="never"),
                 "-c",
                 ~s(sandbox_mode="danger-full-access"),
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: f.workspace,
             inherit_env: [],
             env: %{
               "HOME" => f.home,
               "CODEX_HOME" => f.codex_home,
               "TMPDIR" => ctx.root,
               "PATH" => f.bin <> ":/usr/bin:/bin",
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    connection = :sys.get_state(pid).connection

    on_exit(fn ->
      monitor = Process.monitor(connection.owner.pid)
      assert :ok = StdioSessionFixture.close(pid, connection)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
      assert :atomics.get(connection.owner.completion, 1) == 1
      assert Port.info(connection.port) == nil
    end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_dynamic_tool_exposure", "version" => "0.1.0"},
               %{
                 "experimentalApi" => true,
                 "optOutNotificationMethods" => ["remoteControl/status/changed"]
               }
             )

    pid
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
