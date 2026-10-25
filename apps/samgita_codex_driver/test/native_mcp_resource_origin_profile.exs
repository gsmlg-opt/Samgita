defmodule SamgitaCodexDriver.NativeMcpResourceOriginProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  import TurnFixture, only: [call: 3, upstream_error: 3]

  @moduletag :real_codex
  @moduletag :isolated_mcp_origin
  @moduletag timeout: 60_000
  @script Path.expand("support/native_mcp_resource_origin_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @uri "ui://widget/checkout-session.html"
  @calls [{"owned-origin-best-buy", "best_buy"}, {"owned-origin-walmart", "walmart"}]
  @not_found %{
    "code" => -32_603,
    "message" => "originating MCP tool call was not found or did not complete successfully"
  }

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert hash(File.read!(binary)) == @binary_sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-mcp-origin-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, binary: Path.expand(binary)}
  end

  test "native model origins select their original app and account despite conflicting read hints",
       ctx do
    native = start(ctx)
    pid = native.pid
    root = thread(ctx, pid)
    assert File.ls!(Path.join(ctx.root, "workspace")) == []
    assert rows(ctx, "model") == []
    assert rows(ctx, "tool_call") == []
    assert rows(ctx, "resource_read") == []

    # The fixed future model call ID is not yet native provenance.
    assert_guard(ctx, pid, read_params(root, "owned-origin-best-buy"), @not_found)

    turn =
      TurnFixture.start_turn(pid, root, [
        %{"type" => "text", "text" => "OWNED_MCP_ORIGIN_V43"}
      ])

    events = TurnFixture.finish_turn(pid, root, turn)
    assert_native_origins(events, root, turn)
    assert_provider(ctx, root)
    assert rows(ctx, "resource_read") == []

    for {origin, connector} <- @calls do
      other = if connector == "best_buy", do: "walmart", else: "best_buy"

      params =
        read_params(root, origin)
        |> Map.put("connectorId", other)
        |> Map.put("target", %{"connectorId" => other, "linkId" => "link_" <> other})

      assert call(pid, "mcpServer/resource/read", params) === %{
               "contents" => [
                 %{
                   "uri" => @uri,
                   "mimeType" => "text/html",
                   "text" => "<html>" <> connector <> "</html>"
                 }
               ],
               "originCallId" => origin
             }
    end

    assert rows(ctx, "resource_read") === [
             %{
               "event" => "resource_read",
               "uri" => @uri,
               "thread_id" => root,
               "connector" => "best_buy",
               "link_id" => "link_best_buy"
             },
             %{
               "event" => "resource_read",
               "uri" => @uri,
               "thread_id" => root,
               "connector" => "walmart",
               "link_id" => "link_walmart"
             }
           ]

    # Generated thread IDs are independently supplied by native management.
    other_thread = thread(ctx, pid)
    refute other_thread == root
    assert_guard(ctx, pid, read_params(other_thread, "owned-origin-best-buy"), @not_found)
    assert_guard(ctx, pid, read_params(root, "owned-origin-never-produced"), @not_found)

    assert_guard(
      ctx,
      pid,
      Map.put(read_params(root, "owned-origin-walmart"), "uri", "ui://widget/wrong.html"),
      %{
        "code" => -32_603,
        "message" => "originating MCP tool call does not match the requested resource"
      }
    )

    assert_guard(
      ctx,
      pid,
      Map.delete(read_params(root, "owned-origin-best-buy"), "threadId"),
      %{"code" => -32_600, "message" => "originCallId requires threadId"}
    )

    assert_provider(ctx, root)
    assert File.ls!(Path.join(ctx.root, "workspace")) == []
    assert {:ok, remaining} = Session.drain(pid)
    refute Enum.any?(remaining, &(&1.kind == :server_request))
    assert_idle(pid)
    assert_profile(ctx, native)
    close(ctx, native)
  end

  defp assert_guard(ctx, pid, params, error) do
    before = %{
      reads: rows(ctx, "resource_read"),
      tools: rows(ctx, "tool_call"),
      model: rows(ctx, "model")
    }

    assert upstream_error(pid, "mcpServer/resource/read", params) === error

    assert %{
             reads: rows(ctx, "resource_read"),
             tools: rows(ctx, "tool_call"),
             model: rows(ctx, "model")
           } === before
  end

  defp assert_native_origins(events, root, turn) do
    for method <- ["item/started", "item/completed"] do
      selected =
        Enum.filter(events, fn event ->
          event.wire["method"] == method and
            get_in(event.wire, ["params", "item", "type"]) == "mcpToolCall"
        end)

      assert Enum.map(selected, & &1.wire["params"]["item"]["id"]) ==
               Enum.map(@calls, &elem(&1, 0))

      for {event, {origin, connector}} <- Enum.zip(selected, @calls) do
        params = event.wire["params"]
        assert params["threadId"] == root
        assert params["turnId"] == turn
        item = params["item"]

        assert Map.take(item, [
                 "id",
                 "type",
                 "server",
                 "tool",
                 "arguments",
                 "appContext",
                 "mcpAppResourceUri",
                 "mcpAppUi",
                 "pluginId",
                 "readOnlyHint",
                 "error"
               ]) === %{
                 "id" => origin,
                 "type" => "mcpToolCall",
                 "server" => "codex_apps",
                 "tool" => connector <> "_product_search",
                 "arguments" => %{"query" => "lamps", "link_id" => "link_" <> connector},
                 "appContext" => %{
                   "connectorId" => connector,
                   "linkId" => "link_" <> connector,
                   "resourceUri" => @uri,
                   "appName" => connector,
                   "actionName" => connector <> "_product_search"
                 },
                 "mcpAppResourceUri" => @uri,
                 "mcpAppUi" => nil,
                 "pluginId" => nil,
                 "readOnlyHint" => true,
                 "error" => nil
               }

        assert_tool_result(method, item, connector)
      end
    end
  end

  defp assert_tool_result("item/completed", item, connector) do
    assert item["status"] == "completed"

    assert item["result"] === %{
             "_meta" => nil,
             "content" => [%{"type" => "text", "text" => "Owned origin tool " <> connector}],
             "structuredContent" => %{"connector" => connector, "products" => []}
           }

    assert is_integer(item["durationMs"]) and item["durationMs"] >= 0
  end

  defp assert_tool_result("item/started", item, _connector) do
    assert item["status"] == "inProgress"
    assert item["result"] == nil
  end

  defp assert_provider(ctx, root) do
    assert rows(ctx, "tool_call") === [
             %{
               "event" => "tool_call",
               "connector" => "best_buy",
               "thread_id" => root,
               "arguments" => %{"query" => "lamps", "link_id" => "link_best_buy"},
               "sequence" => 1
             },
             %{
               "event" => "tool_call",
               "connector" => "walmart",
               "thread_id" => root,
               "arguments" => %{"query" => "lamps", "link_id" => "link_walmart"},
               "sequence" => 2
             }
           ]

    assert rows(ctx, "model") === [
             %{"event" => "model", "sequence" => 1, "output_call_ids" => []},
             %{
               "event" => "model",
               "sequence" => 2,
               "output_call_ids" => ["owned-origin-best-buy"]
             },
             %{
               "event" => "model",
               "sequence" => 3,
               "output_call_ids" => ["owned-origin-best-buy", "owned-origin-walmart"]
             }
           ]

    requests = ctx.root |> Path.join("model-requests.json") |> File.read!() |> JSON.decode!()
    assert length(requests) == 3
    assert Enum.all?(requests, &(&1["model"] == "mock-model"))
    assert rows(ctx, "fatal") == []
  end

  defp assert_profile(ctx, native) do
    proof = journal(ctx)["namespace"]
    assert proof["parent"] == File.read_link!("/proc/self/ns/net")
    refute proof["child"] == proof["parent"]
    assert proof["interfaces"] == ["lo"]
    assert proof["default_route"] == false
    assert File.read_link!("/proc/#{native.started["pid"]}/ns/net") == proof["child"]
    assert call(native.pid, "server/diagnostics", %{})["process"]["id"] == native.started["pid"]
    assert rows(ctx, "fatal") == []

    assert Enum.all?(rows(ctx, "mcp"), &(&1["bearer_absent"] and &1["account_absent"]))
    assert rows(ctx, "negotiated") != []
    assert Enum.all?(rows(ctx, "negotiated"), &(&1["selected"] == "2025-06-18"))

    auth = ctx.root |> Path.join("codex/auth.json") |> File.read!() |> JSON.decode!()
    assert auth["auth_mode"] == "chatgpt"
    assert File.stat!(Path.join(ctx.root, "codex/auth.json")).mode |> Bitwise.band(0o777) == 0o600

    for path <- ["origin-journal.json", "model-requests.json", "native-stderr.log"],
        secret <- Map.values(auth["tokens"]),
        is_binary(secret) and secret != "" do
      refute File.read!(Path.join(ctx.root, path)) =~ secret
    end
  end

  defp start(ctx) do
    {:ok, pid} =
      Session.start_link(
        request_timeout_ms: 10_000,
        transport:
          {Stdio,
           [
             executable: System.find_executable("python3"),
             args: ["-B", @script, "--root", ctx.root, "--codex", ctx.binary],
             cwd: ctx.root,
             inherit_env: [],
             env: %{
               "CODEX_HOME" => Path.join(ctx.root, "codex"),
               "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
               "PYTHONDONTWRITEBYTECODE" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    %{connection: connection} = :sys.get_state(pid)

    on_exit(fn ->
      assert :ok = StdioSessionFixture.close(pid, connection)

      for row <- rows(ctx, "native_started"),
          key <- ["pid", "controller_pid", "namespace_owner_pid"],
          do: await_exit(row[key], System.monotonic_time(:millisecond) + 5_000)
    end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_owned_mcp_origin", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    started = await_started(ctx, pid, System.monotonic_time(:millisecond) + 5_000)
    %{pid: pid, connection: connection, started: started}
  end

  defp thread(ctx, pid) do
    id =
      call(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => Path.join(ctx.root, "workspace"),
        "sandbox" => "read-only",
        "approvalPolicy" => "on-request",
        "historyMode" => "paginated",
        "ephemeral" => false
      })["thread"]["id"]

    assert is_binary(id) and byte_size(id) > 0
    id
  end

  defp close(ctx, native) do
    assert :ok = StdioSessionFixture.close(native.pid, native.connection)

    for key <- ["pid", "controller_pid", "namespace_owner_pid"],
        do: await_exit(native.started[key], System.monotonic_time(:millisecond) + 5_000)

    assert rows(ctx, "native_closed") == [%{"event" => "native_closed"}]
    assert rows(ctx, "fatal") == []
    assert File.ls!(Path.join(ctx.root, "workspace")) == []
  end

  defp await_started(ctx, pid, deadline) do
    case rows(ctx, "native_started") do
      [started] ->
        started

      [] ->
        assert System.monotonic_time(:millisecond) < deadline, "Owned native readiness deadline"

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
        after
          10 -> :ok
        end

        await_started(ctx, pid, deadline)
    end
  end

  defp await_exit(pid, deadline) do
    if File.exists?("/proc/#{pid}") do
      assert System.monotonic_time(:millisecond) < deadline, "Owned process #{pid} not reaped"

      receive do
      after
        10 -> :ok
      end

      await_exit(pid, deadline)
    end
  end

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.interaction_outcomes(pid) == []
    assert Session.uncertain_operations(pid) == []
  end

  defp read_params(thread, origin),
    do: %{"threadId" => thread, "originCallId" => origin, "server" => "codex_apps", "uri" => @uri}

  defp journal(ctx) do
    path = Path.join(ctx.root, "origin-journal.json")
    if File.exists?(path), do: path |> File.read!() |> JSON.decode!(), else: %{"events" => []}
  end

  defp rows(ctx, event), do: Enum.filter(journal(ctx)["events"], &(&1["event"] == event))
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
