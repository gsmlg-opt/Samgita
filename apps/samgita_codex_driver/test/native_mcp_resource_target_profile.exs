defmodule SamgitaCodexDriver.NativeMcpResourceTargetProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  import TurnFixture, only: [call: 3, upstream_error: 3]

  @moduletag :real_codex
  @moduletag :isolated_mcp_target
  @moduletag timeout: 60_000
  @script Path.expand("support/native_mcp_resource_target_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @uri "test://codex/resource"
  @private_uri "test://codex/private"
  @invalid_target %{
    "code" => -32_600,
    "message" => "target requires codex_apps, a connectorId, and a real linkId or null"
  }
  @denied %{
    "code" => -32_042,
    "message" => "resource authorization required",
    "data" => %{
      "fixture" => "target-policy",
      "requiredConnector" => "calendar",
      "requiredLink" => "link_calendar"
    }
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
        "samgita-mcp-target-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, binary: Path.expand(binary)}
  end

  test "native target resource reads retain flat scope, nulls and backend authorization", ctx do
    native = start(ctx)
    pid = native.pid
    thread = thread(ctx, pid)
    bindings = [%{}, %{"threadId" => thread}]

    assert rows(ctx, "resource_read") == []
    expected = Enum.flat_map(bindings, &assert_variants(ctx, pid, &1))
    assert length(expected) == 10
    assert rows(ctx, "resource_read") === expected
    assert rows(ctx, "resource_request_shape") === request_shapes()

    for binding <- bindings do
      assert_native_guards(ctx, pid, binding)
    end

    assert rows(ctx, "resource_read") === expected

    expected = expected ++ Enum.flat_map(bindings, &assert_peer_denials(ctx, pid, &1))
    assert rows(ctx, "resource_read") === expected

    # A rejected peer scope does not poison or authorize a later independent read.
    for binding <- bindings do
      extra = %{"target" => %{"connectorId" => "calendar", "linkId" => "link_calendar"}}
      assert_read(pid, Map.merge(binding, extra), "Owned linked calendar resource\n")
    end

    linked = %{"connector_id" => "calendar", "link_id" => "link_calendar"}
    assert rows(ctx, "resource_read") === expected ++ List.duplicate(read_row(@uri, linked), 2)

    # Native archival materializes this owned empty thread without creating a turn.
    assert call(pid, "thread/archive", %{"threadId" => thread}) === %{}
    archived = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})
    assert archived["thread"]["turns"] == []
    assert archived["thread"]["status"] == %{"type" => "notLoaded"}

    assert File.ls!(Path.join(ctx.root, "workspace")) == []
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request))
    refute Enum.any?(events, &String.starts_with?(&1.wire["method"] || "", "turn/"))
    assert_idle(pid)
    assert_profile(ctx, native)
    close(ctx, native)
  end

  defp variants do
    [
      {%{}, %{}, "Owned generic resource\n"},
      {%{"target" => nil}, %{}, "Owned generic resource\n"},
      {%{"target" => %{"connectorId" => "calendar", "linkId" => "link_calendar"}},
       %{"connector_id" => "calendar", "link_id" => "link_calendar"},
       "Owned linked calendar resource\n"},
      {%{"target" => %{"connectorId" => "calendar", "linkId" => nil}},
       %{"connector_id" => "calendar", "link_id" => nil}, "Owned public calendar resource\n"},
      {%{"connectorId" => "calendar"}, %{"legacy_selected_connector_ids" => ["calendar"]},
       "Owned legacy filtered resource\n"}
    ]
  end

  defp request_shapes do
    for threaded <- [false, true],
        {present, null} <- [
          {false, false},
          {true, true},
          {true, false},
          {true, false},
          {false, false}
        ] do
      %{
        "event" => "resource_request_shape",
        "target_present" => present,
        "target_null" => null,
        "thread_present" => threaded,
        "origin_present" => false
      }
    end
  end

  defp assert_variants(_ctx, pid, binding) do
    for {extra, scope, text} <- variants() do
      assert_read(pid, Map.merge(binding, extra), text)
      read_row(@uri, scope)
    end
  end

  defp assert_read(pid, extra, text) do
    params = Map.merge(%{"server" => "codex_apps", "uri" => @uri}, extra)

    assert call(pid, "mcpServer/resource/read", params) === %{
             "contents" => [%{"uri" => @uri, "mimeType" => "text/plain", "text" => text}],
             "originCallId" => nil
           }
  end

  defp assert_native_guards(ctx, pid, binding) do
    linked = %{"connectorId" => "calendar", "linkId" => "link_calendar"}

    invalid = [
      %{"server" => "fixture", "target" => linked},
      %{"target" => %{"connectorId" => " ", "linkId" => "link_calendar"}},
      %{"target" => %{"connectorId" => "calendar", "linkId" => " "}},
      %{"target" => %{"connectorId" => "calendar", "linkId" => "synthetic_link::fixture"}}
    ]

    for extra <- invalid do
      assert_guard(ctx, pid, Map.merge(binding, extra), @invalid_target)
    end

    unknown = "00000000-0000-4000-8000-000000000000"

    assert_guard(
      ctx,
      pid,
      %{"threadId" => unknown, "target" => linked},
      %{"code" => -32_600, "message" => "thread not found: " <> unknown}
    )
  end

  defp assert_guard(ctx, pid, extra, error) do
    before = rows(ctx, "resource_read")
    params = Map.merge(%{"server" => "codex_apps", "uri" => @uri}, extra)
    assert upstream_error(pid, "mcpServer/resource/read", params) === error
    assert rows(ctx, "resource_read") === before
  end

  defp peer_denials do
    [
      {%{"target" => %{"connectorId" => "calendar", "linkId" => "link_other"}},
       %{"connector_id" => "calendar", "link_id" => "link_other"}},
      {%{"target" => %{"connectorId" => "unknown", "linkId" => "link_unknown"}},
       %{"connector_id" => "unknown", "link_id" => "link_unknown"}},
      {%{"uri" => @private_uri, "target" => %{"connectorId" => "calendar", "linkId" => nil}},
       %{"connector_id" => "calendar", "link_id" => nil}},
      {%{"connectorId" => "unknown"}, %{"legacy_selected_connector_ids" => ["unknown"]}},
      {%{
         "connectorId" => "other",
         "target" => %{"connectorId" => "calendar", "linkId" => "link_calendar"}
       },
       %{
         "connector_id" => "calendar",
         "link_id" => "link_calendar",
         "legacy_selected_connector_ids" => ["other"]
       }}
    ]
  end

  defp assert_peer_denials(ctx, pid, binding) do
    for {extra, scope} <- peer_denials() do
      params = Map.merge(%{"server" => "codex_apps", "uri" => @uri}, Map.merge(binding, extra))
      before = rows(ctx, "resource_read")
      assert upstream_error(pid, "mcpServer/resource/read", params) === @denied

      row = %{
        "event" => "resource_read",
        "uri" => params["uri"],
        "scope" => scope,
        "result" => "denied"
      }

      assert rows(ctx, "resource_read") === before ++ [row]
      row
    end
  end

  defp read_row(uri, scope),
    do: %{"event" => "resource_read", "uri" => uri, "scope" => scope, "result" => "accepted"}

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
               %{"name" => "samgita_owned_mcp_target", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    [started] = rows(ctx, "native_started")
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
        "historyMode" => "paginated"
      })["thread"]["id"]

    assert is_binary(id) and byte_size(id) > 0
    id
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
    assert rows(ctx, "negotiated") != []
    assert Enum.all?(rows(ctx, "negotiated"), &(&1["selected"] == "2025-06-18"))
    assert Enum.all?(rows(ctx, "mcp"), &(&1["bearer_absent"] and &1["account_absent"]))
    refute Enum.any?(rows(ctx, "mcp"), &(&1["method"] == "tools/call"))
    assert File.ls!(Path.join(ctx.root, "workspace")) == []

    auth = ctx.root |> Path.join("codex/auth.json") |> File.read!() |> JSON.decode!()
    assert auth["auth_mode"] == "chatgpt"
    assert File.stat!(Path.join(ctx.root, "codex/auth.json")).mode |> Bitwise.band(0o777) == 0o600

    for path <- ["target-journal.json", "native-stderr.log"],
        secret <- Map.values(auth["tokens"]),
        is_binary(secret) and secret != "" do
      refute File.read!(Path.join(ctx.root, path)) =~ secret
    end
  end

  defp close(ctx, native) do
    assert :ok = StdioSessionFixture.close(native.pid, native.connection)

    for key <- ["pid", "controller_pid", "namespace_owner_pid"],
        do: await_exit(native.started[key], System.monotonic_time(:millisecond) + 5_000)

    assert rows(ctx, "native_closed") == [%{"event" => "native_closed"}]
    assert rows(ctx, "fatal") == []
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

  defp journal(ctx) do
    path = Path.join(ctx.root, "target-journal.json")
    if File.exists?(path), do: path |> File.read!() |> JSON.decode!(), else: %{"events" => []}
  end

  defp rows(ctx, event), do: Enum.filter(journal(ctx)["events"], &(&1["event"] == event))
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
