defmodule SamgitaCodexDriver.NativeOrdinaryRemotePluginLimitTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_remote_plugin_limit_fixture.py", __DIR__)
  @script_sha "7b2542fad04422726ca39507ec7525f68407f31166162f51795f2f490ca9ede7"
  @base Path.expand("../../../scripts/codex/ordinary_app_context_fixture.py", __DIR__)
  @base_sha "2f25436a2b5694390d64305b9566ce3859eea5cb81f8b212c125eb05db4126e1"
  @schema Path.expand(
            "../../samgita_protocol_codex/priv/upstream/0.163.0/experimental/v2/PluginSearchParams.json",
            __DIR__
          )
  @schema_sha "9a531ed727cf716302e611d98153f4ed09598b7b27a5629074648c0e57f24e09"
  @query "owned ordinary remote limit marker"
  @market "created-by-me-remote"
  @cases [
    {4749, %{}, 16, 16},
    {"4749", %{"limit" => nil}, 16, 16},
    {"owned-limit-zero", %{"limit" => 0}, 1, 1},
    {"owned-limit-one", %{"limit" => 1}, 1, 1},
    {"owned-limit-seventeen", %{"limit" => 17}, 17, 17},
    {"owned-limit-upper", %{"limit" => 1001}, 1000, 18}
  ]

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio
    alias SamgitaProtocolCodex.Error

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      case Stdio.send(state, encoded) do
        {:ok, next} ->
          case record(next, :out, encoded) do
            :ok -> {:ok, next}
            {:error, error} -> {:error, error, next}
          end

        other ->
          other
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          case record_events(next, events) do
            :ok -> {:ok, events, next}
            {:error, error} -> {:error, error, next}
          end

        other ->
          other
      end
    end

    defp record_events(state, events) do
      Enum.reduce_while(events, :ok, fn
        {:message, encoded}, :ok ->
          case record(state, :in, encoded) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end

        _, :ok ->
          {:cont, :ok}
      end)
    end

    defp record(state, direction, encoded) do
      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(encoded)
        limit = if direction == :out, do: 8192, else: 65_536

        if length(ledger.frames) < 64 and size <= limit and ledger.bytes + size <= 1_048_576 do
          frame = %{direction: direction, encoded: encoded, wire: JSON.decode!(encoded)}
          {:ok, %{frames: ledger.frames ++ [frame], bytes: ledger.bytes + size}}
        else
          {{:error, Error.new(:test_capture_overflow)}, ledger}
        end
      end)
    end

    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert hash(File.read!(binary)) === @binary_sha
    assert hash(File.read!(@script)) === @script_sha
    assert hash(File.read!(@base)) === @base_sha
    assert hash(File.read!(@schema)) === @schema_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-remote-plugin-limit-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "ordinary-remote-plugin-limit")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    ctx = %{
      binary: Path.expand(binary),
      root: root,
      fixture: fixture,
      capture: start_supervised!({Agent, fn -> %{frames: [], bytes: 0} end})
    }

    on_exit(fn -> close_provider(ctx) end)
    config = Path.join(fixture.codex_home, "config.toml")
    startup = File.read!(config)
    marker = "plugins = false\nremote_plugin = false\n"
    assert length(:binary.matches(startup, marker)) === 1

    enabled =
      String.replace(startup, marker, "plugins = true\nremote_plugin = true\n", global: false)

    paths = [
      @script,
      @base,
      @schema,
      fixture.requests,
      Path.join(fixture.codex_home, "models.json"),
      Path.join(root, "ordinary-remote-plugin-limit-rows.json"),
      Path.join(__DIR__, "support/model_fixture.ex"),
      Path.join(__DIR__, "support/stdio_session_fixture.ex")
    ]

    Map.merge(ctx, %{
      config: config,
      startup: startup,
      enabled: enabled,
      inputs: Map.new(paths, &{&1, snapshot(&1)})
    })
  end

  test "ordinary remote plugin search consumes normalized limits and unchanged continuation",
       ctx do
    native = start(ctx)
    enable_discovery(ctx)
    assert ModelFixture.requests(ctx.fixture) === []
    assert rows(ctx, "search") === []
    assert_fixture_rows(ctx)

    pages =
      Enum.with_index(@cases, 1)
      |> Enum.map(fn {{id, extra, remote_limit, count}, sequence} ->
        result = search(ctx, native.pid, id, extra, Enum.to_list(1..count))
        assert_backend(ctx, sequence, remote_limit, Enum.to_list(1..count), nil)
        assert_controls(ctx)
        result
      end)

    # The actual native opaque token is returned unchanged to the next request.
    cursor = Map.fetch!(Enum.at(pages, 4), "nextCursor")
    assert cursor === "owned-limit-offset-17"

    search(ctx, native.pid, "owned-limit-continuation", %{"limit" => 17, "cursor" => cursor}, [18])

    assert_backend(ctx, 7, 17, [18], cursor)

    assert call(ctx, native.pid, "thread/loaded/list", %{}) === %{
             "data" => [],
             "nextCursor" => nil
           }

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(native.pid)

    assert Session.uncertain_operations(native.pid) === []
    assert {:ok, events} = Session.drain(native.pid, 128)

    refute Enum.any?(
             events,
             &(&1.kind === :server_request or
                 &1.wire["method"] in ~w(error turn/started turn/completed))
           )

    assert {:ok, []} = Session.drain(native.pid, 128)
    assert_inventory(ctx)
    assert_controls(ctx)
    close_native(native)
    assert_controls(ctx)
    close_provider(ctx)
    assert_controls(ctx)
    assert length(rows(ctx, "search")) === 7
    assert length(rows(ctx, "search_response_sent")) === 7
  end

  defp search(ctx, pid, id, extra, indices) do
    params =
      Map.merge(
        %{
          "searchTerm" => "  " <> @query <> "  ",
          "scope" => "personal",
          "cwds" => [ctx.fixture.workspace]
        },
        extra
      )

    document = @schema |> File.read!() |> JSON.decode!()

    if Map.has_key?(extra, "limit") do
      assert :ok = Schema.validate(document["properties"]["limit"], extra["limit"], max_depth: 8)
    end

    result = call(ctx, pid, %{"id" => id, "method" => "plugin/search", "params" => params})
    assert Enum.sort(Map.keys(result)) === ~w(data nextCursor)
    candidates = Enum.map(result["data"], &ordinary_projection/1)
    ids = Enum.map(candidates, & &1["plugin"]["id"])
    assert length(candidates) === length(indices)
    assert length(Enum.uniq(ids)) === length(ids)
    assert Map.new(Enum.zip(ids, candidates)) === Map.new(indices, &{identity(&1), expected(&1)})
    next = if List.last(indices) < 18, do: "owned-limit-offset-#{List.last(indices)}", else: nil
    assert Map.fetch!(result, "nextCursor") === next
    result
  end

  defp ordinary_projection(candidate) do
    plugin = Map.fetch!(candidate, "plugin")

    %{
      "marketplaceName" => Map.fetch!(candidate, "marketplaceName"),
      "marketplacePath" => Map.fetch!(candidate, "marketplacePath"),
      "plugin" =>
        Map.merge(
          Map.take(plugin, ~w(id remotePluginId name version source keywords)),
          %{"interface" => Map.take(Map.fetch!(plugin, "interface"), ["displayName"])}
        )
    }
  end

  defp expected(index) do
    suffix = suffix(index)

    %{
      "marketplaceName" => @market,
      "marketplacePath" => nil,
      "plugin" => %{
        "id" => identity(index),
        "remotePluginId" => "plugins~Plugin_ordinary_limit_#{suffix}",
        "name" => "ordinary-limit-#{suffix}",
        "version" => "1.0.0",
        "source" => %{"type" => "remote"},
        "keywords" => [@query],
        "interface" => %{"displayName" => "Owned remote limit #{suffix} λ"}
      }
    }
  end

  defp plain(index),
    do: %{
      "remoteId" => "plugins~Plugin_ordinary_limit_#{suffix(index)}",
      "name" => "ordinary-limit-#{suffix(index)}",
      "displayName" => "Owned remote limit #{suffix(index)} λ"
    }

  defp identity(index), do: "ordinary-limit-#{suffix(index)}@#{@market}"
  defp suffix(index), do: index |> Integer.to_string() |> String.pad_leading(2, "0")

  defp assert_backend(ctx, count, limit, indices, token) do
    searches = rows(ctx, "search")
    assert length(searches) === count
    row = List.last(searches)
    assert row["sequence"] === count and row["path"] === "/backend-api/ps/plugins/search"
    query = %{"q" => [@query], "scope" => ["USER"], "limit" => [Integer.to_string(limit)]}
    query = if token, do: Map.put(query, "pageToken", [token]), else: query
    assert row["query"] === query

    assert URI.decode_query(row["rawQuery"]) ===
             Map.new(query, fn {key, [value]} -> {key, value} end)

    assert row["items"] === Enum.map(indices, &plain/1)
    next = if List.last(indices) < 18, do: "owned-limit-offset-#{List.last(indices)}", else: nil
    assert row["nextToken"] === next

    assert is_integer(row["responseSize"]) and 0 < row["responseSize"] and
             row["responseSize"] <= 65_536

    assert row["responseSha256"] =~ ~r/^[a-f0-9]{64}$/
    await(fn -> length(rows(ctx, "search_response_sent")) === count end, now() + 5_000)
    assert length(rows(ctx, "search_response_sent")) === count
  end

  defp assert_fixture_rows(ctx) do
    path = Path.join(ctx.root, "ordinary-remote-plugin-limit-rows.json")
    assert JSON.decode!(File.read!(path)) === Enum.map(1..18, &plain/1)
  end

  defp enable_discovery(ctx) do
    assert File.read!(ctx.config) === ctx.startup
    pending = ctx.config <> ".ordinary-pending"
    File.write!(pending, ctx.enabled, [:exclusive])
    File.rename!(pending, ctx.config)
  end

  defp assert_controls(ctx) do
    for {path, before} <- ctx.inputs, do: assert(snapshot(path) === before)
    assert File.read!(ctx.config) === ctx.enabled
    assert ModelFixture.requests(ctx.fixture) === []
    assert File.ls!(ctx.fixture.workspace) === []
    assert Path.wildcard(Path.join(ctx.fixture.codex_home, "sessions/**/rollout-*.jsonl")) === []
    assert rows(ctx, "unexpected_http") === []
    assert rows(ctx, "fixture_error") === []
  end

  defp start(ctx) do
    args = [
      "-c",
      ~s(approval_policy="never"),
      "-c",
      ~s(sandbox_mode="danger-full-access"),
      "-c",
      "features.recommended_plugins=false",
      "app-server",
      "--listen",
      "stdio://"
    ]

    assert {:ok, pid} =
             Session.start_link(
               max_events: 128,
               max_event_bytes: 1_048_576,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args: args,
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    max_message_bytes: 65_536,
                    env: %{
                      "HOME" => ctx.fixture.home,
                      "CODEX_HOME" => ctx.fixture.codex_home,
                      "TMPDIR" => ctx.root,
                      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
                      "SHELL" => "/bin/sh",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)
    id = request_id()
    info = %{"name" => "owned_ordinary_remote_plugin_limit", "version" => "1"}
    capabilities = %{"experimentalApi" => true}

    wire = %{
      "id" => id,
      "method" => "initialize",
      "params" => %{"clientInfo" => info, "capabilities" => capabilities}
    }

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    %{pid: pid, connection: connection, native: native}
  end

  defp call(ctx, pid, method, params),
    do: call(ctx, pid, %{"id" => request_id(), "method" => method, "params" => params})

  defp call(ctx, pid, wire) do
    id = wire["id"]

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    result
  end

  defp assert_exchange(ctx, wire, response) do
    assert [sent] = Enum.filter(frames(ctx, :out), &(&1.wire["id"] === wire["id"]))
    assert [received] = Enum.filter(frames(ctx, :in), &(&1.wire["id"] === wire["id"]))
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert {:ok, decoded} = Wire.decode(sent.encoded, max_depth: 32)
    assert decoded === wire
    assert {:ok, decoded} = Wire.decode(received.encoded, max_depth: 32)
    assert decoded === response
    assert Enum.sort(Map.keys(response)) === ~w(id result)
  end

  defp assert_inventory(ctx) do
    outgoing = frames(ctx, :out)

    assert Enum.map(outgoing, & &1.wire["method"]) ===
             ~w(initialize initialized server/diagnostics plugin/search plugin/search plugin/search plugin/search plugin/search plugin/search plugin/search thread/loaded/list)

    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))

    responses =
      Enum.filter(
        frames(ctx, :in),
        &(Map.has_key?(&1.wire, "id") and not Map.has_key?(&1.wire, "method"))
      )

    assert length(requests) === 10 and length(responses) === 10
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(Enum.uniq(ids)) === 10
    assert MapSet.new(Enum.map(responses, & &1.wire["id"])) === MapSet.new(ids)
    expected = Enum.map(@cases, &elem(&1, 0)) ++ ["owned-limit-continuation"]

    assert Enum.map(
             Enum.filter(requests, &(&1.wire["method"] === "plugin/search")),
             & &1.wire["id"]
           ) === expected
  end

  defp frames(ctx, direction),
    do:
      Agent.get(
        ctx.capture,
        &Enum.filter(&1.frames, fn frame -> frame.direction === direction end)
      )

  defp close_native(native) do
    monitor = Process.monitor(native.connection.owner.pid)
    assert :ok = Session.close(native.pid)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(native.connection.owner.completion, 1) === 1
    assert Port.info(native.connection.port) === nil
    refute File.exists?("/proc/#{native.native}")
  end

  defp close_provider(ctx) do
    try do
      if rows(ctx, "fixture_closed") === [] do
        path = Path.join(ctx.root, "ordinary-remote-plugin-limit-close.json")

        unless File.exists?(path) do
          pending = path <> ".pending"
          File.write!(pending, JSON.encode!(%{"action" => "close"}), [:exclusive])
          File.rename!(pending, path)
        end

        await(fn -> rows(ctx, "fixture_closed") != [] end, now() + 5_000)
      end
    after
      assert :ok = ModelFixture.close(ctx.fixture)
    end

    assert :atomics.get(ctx.fixture.transport.owner.completion, 1) === 1
    assert Port.info(ctx.fixture.port) === nil
    assert [%{"pid" => helper}] = rows(ctx, "fixture_started")
    assert [%{"pid" => ^helper}] = rows(ctx, "fixture_closed")
    await(fn -> not File.exists?("/proc/#{helper}") end, now() + 5_000)
  end

  defp rows(ctx, event) do
    path = Path.join(ctx.root, "ordinary-remote-plugin-limit-journal.json")

    if File.exists?(path) do
      rows = snapshot(path).bytes |> JSON.decode!() |> Map.fetch!("events")
      assert length(rows) <= 64
      Enum.filter(rows, &(&1["event"] === event))
    else
      []
    end
  end

  defp await(predicate, until) do
    unless predicate.() do
      assert now() < until, "ordinary metadata observation deadline"

      receive do
      after
        10 -> :ok
      end

      await(predicate, until)
    end
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp request_id, do: "ordinary-plugin-limit-#{System.unique_integer([:positive, :monotonic])}"
  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
