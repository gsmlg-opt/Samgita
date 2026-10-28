defmodule SamgitaCodexDriver.NativeOrdinaryRateLimitMetadataTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_rate_limit_metadata_fixture.py", __DIR__)
  @script_sha "f64f18603635d448e9981e1a20d8793c1f1a75820bedac30666fb8c8e2465b5f"
  @cleanup Path.join(__DIR__, "support/stdio_session_fixture.ex")
  @cleanup_sha "a164a57adff4cba26360a7e2788b8c3e9e6829a0a5e77eae28e857c29dc201a0"
  @root_sha "92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352"
  @notification_sha "c626079776d401d358a8791b74cfe6c978d18aabbb78477ce7bd710a79779bc1"
  @marker "Owned ordinary rate-limit metadata λ🙂"
  @quota "account/rateLimits/updated"
  @message "You’ve hit your usage limit. Try again later."
  @literal_bytes "\"rate_limit_reached\"\n"
  @literal_sha "d28b70fcbb690c73033101e03acfb2f02af76c6b6cda78faf02d9a4161bef177"
  @quota_literals [
    {"workspace_owner_credits_depleted", 1,
     "418e3888e855c21751ee536b69d28e353cd84d2b119bb80010d5fa02466999ac"},
    {"workspace_member_credits_depleted", 2,
     "76c10aa6691ddd9ebcc1c61d727f07d6cb268d3918a41fbfa29788dc29cb9a75"},
    {"workspace_owner_usage_limit_reached", 3,
     "153f564270c13fadf038316276b57cdb213ebf8b47f783fe540db8647bc71c33"},
    {"workspace_member_usage_limit_reached", 4,
     "dbb97eef870378cb1707637f30d2610ef0d208c7a410054c8305805abf9c6467"}
  ]
  @reference_bytes """
  {
    "$ref": "#/definitions/RateLimitReachedType"
  }
  """
  @reference_sha "34e8447781fd474dff6e6a415c7e2c66a1932b2612d9590854a821e1cce07f63"
  @known_error_bytes """
  {
    "enum": [
      "contextWindowExceeded",
      "sessionBudgetExceeded",
      "usageLimitExceeded",
      "rateLimitExceeded",
      "flexUnavailable",
      "serverOverloaded",
      "cyberPolicy",
      "misalignmentPolicyViolation",
      "tooManyDenials",
      "internalServerError",
      "unauthorized",
      "badRequest",
      "threadRollbackFailed",
      "sandboxError",
      "other"
    ],
    "type": "string"
  }
  """
  @known_error_sha "35bbfdf0f8a8582ab497ef79ce4c15e32256f77f4fe91eef104ec007924b3e4b"

  # Owner2983 only: the original ordinary quota notification wrapper.
  @quota_wrapper_root_sha "8e719512bc26bb3871fcf7b378b79abf912d82787609c0ad418b71f179d0883f"
  @quota_wrapper_node_sha "5b72f4af340460b1f37e282d303885220f216f2fa62bdf19bf4db8edbaabf3d2"
  @quota_wrapper_node_bytes """
  {
    "properties": {
      "method": {
        "enum": [
          "account/rateLimits/updated"
        ],
        "title": "Account/rateLimits/updatedNotificationMethod",
        "type": "string"
      },
      "params": {
        "$ref": "#/definitions/AccountRateLimitsUpdatedNotification"
      }
    },
    "required": [
      "method",
      "params"
    ],
    "title": "Account/rateLimits/updatedNotification",
    "type": "object"
  }
  """

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
    def send(state, bytes) do
      case Stdio.send(state, bytes) do
        {:ok, next} ->
          case record(next, :out, bytes) do
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
        {:message, bytes}, :ok ->
          case record(state, :in, bytes) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end

        _, :ok ->
          {:cont, :ok}
      end)
    end

    defp record(state, direction, bytes) do
      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(bytes)
        limit = if direction == :out, do: 8192, else: 131_072

        if length(ledger.frames) < 128 and size <= limit and ledger.bytes + size <= 1_048_576 do
          frame = %{direction: direction, encoded: bytes, wire: JSON.decode!(bytes)}
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

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) === @binary_sha

    for {path, sha} <- [
          {@script, @script_sha},
          {@cleanup, @cleanup_sha},
          {schema_path("experimental/ClientRequest.json"), @root_sha},
          {schema_path("experimental/ServerNotification.json"), @notification_sha}
        ],
        do: assert(hash(File.read!(path)) === sha)

    python = System.find_executable("python3") || flunk("BLOCKED_ENV: Python 3 required")

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-ordinary-rate-metadata-" <>
          Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      )

    File.mkdir!(root)
    resources = :atomics.new(2, [])

    on_exit(fn ->
      assert Enum.all?(1..2, &(:atomics.get(resources, &1) in [0, 2])),
             "Owned cleanup unconfirmed; retaining rate metadata fixture #{root}"

      File.rm_rf!(root)
    end)

    for child <- ~w(home codex workspace bin tmp), do: File.mkdir!(Path.join(root, child))
    File.cp!("/bin/sh", Path.join(root, "bin/sh"))

    ctx = %{
      root: root,
      binary: Path.expand(binary),
      python: python,
      home: Path.join(root, "home"),
      codex: Path.join(root, "codex"),
      workspace: Path.join(root, "workspace"),
      bin: Path.join(root, "bin"),
      requests: Path.join(root, "requests.json"),
      resources: resources,
      capture: start_supervised!({Agent, fn -> %{frames: [], bytes: 0} end})
    }

    ctx = Map.merge(ctx, Map.take(tags, [:reached_type, :literal_index, :literal_sha]))
    peer = start_peer(ctx)

    paths = [
      @script,
      @cleanup,
      Path.join(ctx.codex, "config.toml"),
      Path.join(ctx.codex, "models.json"),
      Path.join(ctx.bin, "sh"),
      schema_path("experimental/ClientRequest.json"),
      schema_path("experimental/ServerNotification.json")
    ]

    Map.merge(ctx, %{peer: peer, inputs: Map.new(paths, &{&1, snapshot(&1)})})
  end

  test "native provider 429 publishes ordinary quota type before a failed turn without replay",
       ctx do
    native = start_native(ctx)
    assert_empty_loaded(ctx, native.pid)

    thread =
      call(ctx, native.pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.workspace,
        "ephemeral" => true
      })["thread"]["id"]

    assert is_binary(thread) and byte_size(thread) > 0
    assert_setup(ctx)
    assert snapshot(ctx.requests).bytes |> JSON.decode!() === []
    before_ms = System.system_time(:millisecond)

    turn =
      call(ctx, native.pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => @marker}]
      })["turn"]["id"]

    assert is_binary(turn) and byte_size(turn) > 0
    events = collect(ctx, native.pid, thread, turn, [], now() + 20_000)
    after_ms = System.system_time(:millisecond)
    assert_lifecycle(ctx, events, thread, turn, before_ms, after_ms)
    assert_provider(ctx, thread, turn)
    assert_setup(ctx)
    # These management calls bracket idle state; they never resubmit a turn.
    assert call(ctx, native.pid, "thread/loaded/list", %{}) === %{
             "data" => [thread],
             "nextCursor" => nil
           }

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(native.pid)

    assert Session.uncertain_operations(native.pid) === []
    assert_inventory(ctx)
    requests_before = snapshot(ctx.requests)
    outgoing_before = Enum.filter(frames(ctx), &(&1.direction === :out))
    close_native(native)
    assert snapshot(ctx.requests) === requests_before
    assert Enum.filter(frames(ctx), &(&1.direction === :out)) === outgoing_before
    close_peer(ctx.peer)
    assert snapshot(ctx.requests) === requests_before
    assert_setup(ctx)

    assert rows(ctx, "fixture_closed") === [
             %{"event" => "fixture_closed", "pid" => ctx.peer.native}
           ]
  end

  # These are descriptive dependency-data cases. No real workspace identity,
  # credit state, entitlement or enforcement behavior is selected as an oracle.
  for {literal, index, sha} <- @quota_literals do
    @tag :ordinary_quota_literal
    @tag reached_type: literal, literal_index: index, literal_sha: sha
    test "native provider 429 preserves quota literal #{literal} without replay", ctx do
      run_literal_case(ctx)
    end
  end

  defp run_literal_case(ctx) do
    native = start_native(ctx)
    assert_empty_loaded(ctx, native.pid)

    thread =
      call(ctx, native.pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.workspace,
        "ephemeral" => true
      })["thread"]["id"]

    assert is_binary(thread) and byte_size(thread) > 0
    assert_setup(ctx)
    assert snapshot(ctx.requests).bytes |> JSON.decode!() === []
    before_ms = System.system_time(:millisecond)

    turn =
      call(ctx, native.pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => @marker}]
      })["turn"]["id"]

    assert is_binary(turn) and byte_size(turn) > 0
    events = collect(ctx, native.pid, thread, turn, [], now() + 20_000)
    after_ms = System.system_time(:millisecond)
    assert_lifecycle(ctx, events, thread, turn, before_ms, after_ms)
    assert_provider(ctx, thread, turn)
    assert_setup(ctx)
    # These management calls bracket idle state; they never resubmit a turn.
    assert call(ctx, native.pid, "thread/loaded/list", %{}) === %{
             "data" => [thread],
             "nextCursor" => nil
           }

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(native.pid)

    assert Session.uncertain_operations(native.pid) === []
    assert_inventory(ctx)
    requests_before = snapshot(ctx.requests)
    outgoing_before = Enum.filter(frames(ctx), &(&1.direction === :out))
    close_native(native)
    assert snapshot(ctx.requests) === requests_before
    assert Enum.filter(frames(ctx), &(&1.direction === :out)) === outgoing_before
    close_peer(ctx.peer)
    assert snapshot(ctx.requests) === requests_before
    assert_setup(ctx)

    assert rows(ctx, "fixture_closed") === [
             %{"event" => "fixture_closed", "pid" => ctx.peer.native}
           ]
  end

  defp assert_lifecycle(ctx, events, thread, turn, before_ms, after_ms) do
    assert [started] = Enum.filter(events, &(&1.wire["method"] === "turn/started"))
    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn}} = started.wire["params"]
    assert [quota] = Enum.filter(events, &(&1.wire["method"] === @quota))
    assert [error] = Enum.filter(events, &(&1.wire["method"] === "error"))
    assert [finished] = Enum.filter(events, &(&1.wire["method"] === "turn/completed"))

    assert %{"threadId" => ^thread, "turnId" => ^turn, "willRetry" => false} =
             error.wire["params"]

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "failed"}} =
             finished.wire["params"]

    emitted_error = error.wire["params"]["error"]

    assert_native_error(ctx, emitted_error)

    known_error = schema("experimental/ServerNotification.json")["definitions"]["CodexErrorInfo"]
    known_scalar = Enum.at(known_error["anyOf"], 0)
    assert hash(@known_error_bytes) === @known_error_sha
    assert JSON.decode!(@known_error_bytes) === known_scalar
    assert :ok = Schema.validate(known_scalar, emitted_error["codexErrorInfo"])

    # Preserve complete native error maps and any native-added fields without
    # claiming that this known producer emits an arbitrary future extension.
    assert finished.wire["params"]["turn"]["error"] === emitted_error
    ordered = Enum.filter(events, &(&1.wire["method"] in [@quota, "error", "turn/completed"]))
    assert Enum.map(ordered, & &1.wire["method"]) === [@quota, "error", "turn/completed"]
    assert Enum.filter(events, &(&1.kind === :server_request)) === []

    assert Enum.filter(
             events,
             &(&1.wire["method"] === "item/completed" and
                 &1.wire["params"]["item"]["type"] === "agentMessage")
           ) === []

    snapshot = quota.wire["params"]["rateLimits"]

    assert Map.take(snapshot, ~w(limitId primary secondary rateLimitReachedType)) === %{
             "limitId" => "codex",
             "primary" => %{
               "usedPercent" => 91,
               "windowDurationMins" => 60,
               "resetsAt" => 2_000_000_100
             },
             "secondary" => %{
               "usedPercent" => 32,
               "windowDurationMins" => 1440,
               "resetsAt" => 2_000_000_200
             },
             "rateLimitReachedType" => Map.get(ctx, :reached_type, "rate_limit_reached")
           }

    assert_physical(ctx, snapshot)

    for event <- [quota, error, finished] do
      assert [frame] =
               Enum.filter(frames(ctx), &(&1.direction === :in and &1.wire === event.wire))

      assert JSON.decode!(frame.encoded) === event.wire
      assert {:ok, decoded} = Wire.decode(frame.encoded, max_depth: 64)
      assert decoded === event.wire
      if decoded["method"] === @quota, do: assert_quota_wrapper_binding(decoded)
      emitted = Map.fetch!(decoded, "emittedAtMs")
      assert is_integer(emitted) and emitted > 0 and emitted >= before_ms and emitted <= after_ms
    end
  end

  defp assert_native_error(%{reached_type: _literal}, emitted_error) do
    message = Map.fetch!(emitted_error, "message")
    assert is_binary(message) and String.trim(message) !== ""

    assert Map.take(emitted_error, ~w(codexErrorInfo additionalDetails)) === %{
             "codexErrorInfo" => "usageLimitExceeded",
             "additionalDetails" => nil
           }
  end

  defp assert_native_error(_ctx, emitted_error) do
    assert Map.take(emitted_error, ~w(message codexErrorInfo additionalDetails)) === %{
             "message" => @message,
             "codexErrorInfo" => "usageLimitExceeded",
             "additionalDetails" => nil
           }
  end

  defp assert_quota_wrapper_binding(original) do
    bytes =
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/stable/ServerNotification.json")
      |> File.read!()

    assert hash(bytes) === @quota_wrapper_root_sha
    document = JSON.decode!(bytes)
    node = document |> Map.fetch!("oneOf") |> Enum.fetch!(49)
    assert hash(@quota_wrapper_node_bytes) === @quota_wrapper_node_sha
    assert JSON.decode!(@quota_wrapper_node_bytes) === node

    # Wrapper validation preserves the finite429 metadata/lifecycle oracle.
    # Only each selected physical literal gains new evidence; no wrapper or
    # reference owner gains credit from these additional descriptive-data cases.
    assert :ok =
             Schema.validate(
               Map.put(node, "definitions", Map.fetch!(document, "definitions")),
               original,
               max_depth: 64
             )
  end

  defp assert_physical(ctx, snapshot) do
    root = schema("experimental/ServerNotification.json")
    definitions = Map.fetch!(root, "definitions")
    expected = Map.get(ctx, :reached_type, "rate_limit_reached")
    index = Map.get(ctx, :literal_index, 0)
    literal = definitions["RateLimitReachedType"]["enum"] |> Enum.at(index)
    literal_bytes = if index === 0, do: @literal_bytes, else: JSON.encode!(expected) <> "\n"
    literal_sha = Map.get(ctx, :literal_sha, @literal_sha)

    stable_bytes = File.read!(schema_path("stable/ServerNotification.json"))
    assert hash(stable_bytes) === @quota_wrapper_root_sha
    stable_definitions = JSON.decode!(stable_bytes)["definitions"]
    assert stable_definitions["RateLimitReachedType"] === definitions["RateLimitReachedType"]
    assert Enum.fetch!(stable_definitions["RateLimitReachedType"]["enum"], index) === literal

    reference =
      get_in(definitions, ["RateLimitSnapshot", "properties", "rateLimitReachedType", "anyOf"])
      |> Enum.at(0)

    assert hash(literal_bytes) === literal_sha
    assert hash(@reference_bytes) === @reference_sha
    assert JSON.decode!(literal_bytes) === literal
    assert JSON.decode!(@reference_bytes) === reference
    assert literal === expected
    assert Map.fetch!(snapshot, "rateLimitReachedType") === literal

    assert :ok =
             Schema.validate(
               Map.put(reference, "definitions", definitions),
               snapshot["rateLimitReachedType"]
             )

    assert :ok =
             Schema.validate(
               %{"enum" => [literal], "type" => "string"},
               snapshot["rateLimitReachedType"]
             )
  end

  defp collect(ctx, pid, thread, turn, accumulated, deadline) do
    assert rows(ctx, "fixture_error") === [] and rows(ctx, "unexpected_http") === []
    assert {:ok, fresh} = Session.drain(pid, 128)
    events = accumulated ++ fresh
    assert length(events) <= 128

    completed? =
      Enum.any?(
        events,
        &(&1.wire["method"] === "turn/completed" and
            &1.wire["params"]["threadId"] === thread and &1.wire["params"]["turn"]["id"] === turn)
      )

    if completed? do
      events
    else
      remaining = deadline - now()
      assert remaining > 0, "Owned ordinary rate metadata deadline"

      receive do
        {:codex_driver, ^pid, :events_available} ->
          collect(ctx, pid, thread, turn, events, deadline)

        {:codex_driver, ^pid, {:gap, _}} ->
          flunk("Owned ordinary rate metadata event gap")
      after
        remaining -> flunk("Owned ordinary rate metadata deadline")
      end
    end
  end

  defp assert_provider(ctx, thread, turn) do
    assert rows(ctx, "provider_request") === [
             %{
               "event" => "provider_request",
               "method" => "POST",
               "path" => "/v1/responses",
               "query" => "",
               "status" => 429,
               "sequence" => 1,
               "headers" => %{
                 "x-codex-rate-limit-reached-type" =>
                   Map.get(ctx, :reached_type, "rate_limit_reached"),
                 "x-codex-primary-used-percent" => "91",
                 "x-codex-primary-window-minutes" => "60",
                 "x-codex-primary-reset-at" => "2000000100",
                 "x-codex-secondary-used-percent" => "32",
                 "x-codex-secondary-window-minutes" => "1440",
                 "x-codex-secondary-reset-at" => "2000000200"
               }
             }
           ]

    assert [request] = snapshot(ctx.requests).bytes |> JSON.decode!()
    assert request["model"] === "mock-model"
    metadata = JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

    assert Map.take(metadata, ["thread_id", "turn_id"]) === %{
             "thread_id" => thread,
             "turn_id" => turn
           }

    markers =
      for item <- request["input"],
          item["role"] === "user",
          part <- Map.get(item, "content", []),
          is_map(part),
          part["type"] === "input_text",
          do: part["text"]

    assert Enum.count(markers, &(&1 === @marker)) === 1
  end

  defp assert_inventory(ctx) do
    outgoing = Enum.filter(frames(ctx), &(&1.direction === :out))

    assert Enum.map(outgoing, & &1.wire["method"]) ===
             ~w(initialize initialized server/diagnostics
      thread/loaded/list thread/start turn/start thread/loaded/list)

    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 6 and length(Enum.uniq(ids)) === 6
    replies = Enum.filter(frames(ctx), &(&1.direction === :in and Map.has_key?(&1.wire, "id")))
    assert length(replies) === 6
    assert MapSet.new(Enum.map(replies, & &1.wire["id"])) === MapSet.new(ids)
  end

  defp start_peer(ctx) do
    assert {:ok, transport} =
             Stdio.open(
               executable: ctx.python,
               args:
                 [
                   @script,
                   "--codex-home",
                   ctx.codex,
                   "--workspace",
                   ctx.workspace,
                   "--requests-file",
                   ctx.requests
                 ] ++ reached_type_args(ctx),
               cwd: ctx.workspace,
               inherit_env: [],
               max_message_bytes: 8192,
               env: %{
                 "HOME" => ctx.home,
                 "CODEX_HOME" => ctx.codex,
                 "TMPDIR" => Path.join(ctx.root, "tmp"),
                 "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
                 "PYTHONDONTWRITEBYTECODE" => "1"
               }
             )

    :atomics.put(ctx.resources, 1, 1)
    identity = :atomics.new(1, [])
    on_exit(fn -> close_transport(transport, identity, ctx.resources, 1) end)
    startup = peer_startup(transport.port, <<>>, now() + 5_000)
    native = startup["pid"]
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === hash(File.read!(ctx.python))
    assert is_binary(startup["url"]) and String.starts_with?(startup["url"], "http://127.0.0.1:")
    %{transport: transport, identity: identity, native: native, resources: ctx.resources}
  end

  defp reached_type_args(%{reached_type: literal}), do: ["--reached-type", literal]
  defp reached_type_args(_ctx), do: []

  defp peer_startup(port, bytes, deadline) do
    remaining = deadline - now()
    assert remaining > 0 and byte_size(bytes) <= 8192, "Owned ordinary quota peer startup bound"

    case String.split(bytes, "\n", parts: 2) do
      [line, ""] ->
        JSON.decode!(line)

      [_line, _extra] ->
        flunk("Unexpected owned raw peer startup output")

      [_partial] ->
        receive do
          {^port, {:data, chunk}} -> peer_startup(port, bytes <> chunk, deadline)
          {^port, {:exit_status, status}} -> flunk("Owned ordinary quota peer exited #{status}")
        after
          remaining -> flunk("Owned ordinary quota peer startup deadline")
        end
    end
  end

  defp start_native(ctx) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 128,
               max_event_bytes: 1_048_576,
               max_message_bytes: 131_072,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.workspace,
                    inherit_env: [],
                    max_message_bytes: 131_072,
                    env: %{
                      "HOME" => ctx.home,
                      "CODEX_HOME" => ctx.codex,
                      "TMPDIR" => Path.join(ctx.root, "tmp"),
                      "PATH" => ctx.bin <> ":/usr/bin:/bin",
                      "SHELL" => "/bin/sh",
                      "NO_PROXY" => "*",
                      "no_proxy" => "*",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off",
                      "PYTHONDONTWRITEBYTECODE" => "1",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1"
                    }
                  ]}
             )

    :atomics.put(ctx.resources, 2, 1)
    %{connection: connection} = :sys.get_state(pid)
    identity = :atomics.new(1, [])
    native = %{pid: pid, connection: connection, identity: identity, resources: ctx.resources}
    on_exit(fn -> close_native(native) end)
    id = request_id()
    info = %{"name" => "owned_ordinary_rate_metadata", "version" => "1"}
    capabilities = %{"experimentalApi" => true}

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(
      ctx,
      %{
        "id" => id,
        "method" => "initialize",
        "params" => %{"clientInfo" => info, "capabilities" => capabilities}
      },
      response
    )

    os_pid = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(os_pid) and os_pid > 0
    :atomics.put(identity, 1, os_pid)
    assert hash(File.read!("/proc/#{os_pid}/exe")) === @binary_sha
    native
  end

  defp call(ctx, pid, method, params) do
    id = request_id()
    wire = %{"id" => id, "method" => method, "params" => params}
    assert :ok = Schema.validate(schema("experimental/ClientRequest.json"), wire, max_depth: 64)
    reply = Session.request_native(pid, wire, timeout_ms: 5_000)
    assert rows(ctx, "fixture_error") === [] and rows(ctx, "unexpected_http") === []
    assert {:ok, %{"id" => ^id, "result" => result} = response} = reply
    assert_exchange(ctx, wire, response)
    result
  end

  defp assert_exchange(ctx, wire, response) do
    assert [sent] =
             Enum.filter(frames(ctx), &(&1.direction === :out and &1.wire["id"] === wire["id"]))

    assert [received] =
             Enum.filter(frames(ctx), &(&1.direction === :in and &1.wire["id"] === wire["id"]))

    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert {:ok, decoded} = Wire.decode(received.encoded, max_depth: 64)
    assert decoded === response and Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp assert_empty_loaded(ctx, pid),
    do: assert(call(ctx, pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil})

  defp assert_setup(ctx) do
    for {path, before} <- ctx.inputs, do: assert(snapshot(path) === before)
    assert File.ls!(ctx.workspace) === []
    assert rows(ctx, "fixture_error") === [] and rows(ctx, "unexpected_http") === []

    assert Enum.all?(
             journal(ctx),
             &(&1["event"] in ~w(fixture_started fixture_closed provider_request))
           )
  end

  defp frames(ctx), do: Agent.get(ctx.capture, & &1.frames)

  defp journal(ctx) do
    events =
      snapshot(Path.join(ctx.root, "ordinary-rate-limit-metadata-journal.json")).bytes
      |> JSON.decode!()
      |> Map.fetch!("events")

    assert length(events) <= 32
    events
  end

  defp rows(ctx, event), do: Enum.filter(journal(ctx), &(&1["event"] === event))

  defp close_native(native) do
    monitor = Process.monitor(native.connection.owner.pid)
    assert :ok = StdioSessionFixture.close(native.pid, native.connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert_closed(native.connection, native.identity)
    :atomics.put(native.resources, 2, 2)
  end

  defp close_peer(peer), do: close_transport(peer.transport, peer.identity, peer.resources, 1)

  defp close_transport(connection, identity, resources, slot) do
    monitor = Process.monitor(connection.owner.pid)
    assert :ok = Stdio.close(connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert_closed(connection, identity)
    :atomics.put(resources, slot, 2)
  end

  defp assert_closed(connection, identity) do
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert Port.info(connection.port) === nil
    native = :atomics.get(identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))
  end

  defp snapshot(path) do
    limit =
      if Path.basename(path) === "sh" and Path.basename(Path.dirname(path)) === "bin",
        do: File.stat!("/bin/sh").size,
        else: 1_048_576

    assert File.stat!(path).size <= limit
    bytes = File.read!(path)
    assert byte_size(bytes) <= limit
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp schema(path), do: schema_path(path) |> File.read!() |> JSON.decode!()

  defp schema_path(path),
    do: :samgita_protocol_codex |> :code.priv_dir() |> Path.join("upstream/0.163.0/" <> path)

  defp request_id,
    do: "owned-ordinary-rate-metadata-#{System.unique_integer([:positive, :monotonic])}"

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
