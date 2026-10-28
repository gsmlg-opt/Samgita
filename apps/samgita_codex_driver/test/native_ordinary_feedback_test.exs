defmodule SamgitaCodexDriver.NativeOrdinaryFeedbackTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_feedback_fixture.py", __DIR__)
  @script_sha "ead685953206c9904bb57917e163099ef73990b5a512cd4b79ab1d64c888f5c9"
  @schemas %{
    "ClientRequest.json" => "6b10888f163f569922d42c41e94a98b4261258abc7581c14eca867c3b125dc6f",
    "v2/FeedbackUploadParams.json" =>
      "aa958cd74b37fb28cc49ce22345a1efcda9d4cf5fa47e7cce6949e5366ff8b2e",
    "v2/FeedbackUploadResponse.json" =>
      "d23cb7bfa94f59fbb423b1e042239ac1b6dc344be15c5efc69ef04badff01a91"
  }
  @base "Owned  ordinary\r\nfeedback base\tinstructions λ 🙂."
  @normalized "Owned ordinary feedback base instructions λ 🙂."
  @prompt_hash "89d3502a7c23cdd91d264767194cdda94c703bcadc54ca929b6b49832ecccb32"
  @marker "Owned ordinary feedback context λ 🙂."
  @answer "Owned ordinary feedback turn completed λ 🙂."
  @reason "Owned ordinary feedback report λ 🙂."

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
          case Enum.reduce_while(events, :ok, &record_event(&1, &2, next)) do
            :ok -> {:ok, events, next}
            {:error, error} -> {:error, error, next}
          end

        other ->
          other
      end
    end

    defp record_event({:message, encoded}, :ok, state) do
      case record(state, :in, encoded) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end

    defp record_event(_, :ok, _state), do: {:cont, :ok}

    defp record(state, direction, encoded) do
      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(encoded)

        if length(ledger.frames) < 128 and size <= 262_144 and ledger.bytes + size <= 2_097_152 do
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
    for tool <- ~w(python3 unshare ip openssl), do: assert(System.find_executable(tool))
    for {name, expected} <- @schemas, do: assert(hash(File.read!(schema_path(name))) === expected)
    assert hash(@normalized) === @prompt_hash

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-ordinary-feedback-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    for name <- ~w(home codex workspace tmp), do: File.mkdir!(Path.join(root, name))
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      binary: Path.expand(binary),
      root: root,
      capture: start_supervised!({Agent, fn -> %{frames: [], bytes: 0} end}),
      inputs:
        Map.new([@script | Enum.map(Map.keys(@schemas), &schema_path/1)], &{&1, snapshot(&1)})
    }
  end

  test "ordinary native feedback consumes tags and actual persisted context in two distinct reports",
       ctx do
    native = start(ctx)
    pid = native.pid
    config = Path.join(ctx.root, "codex/config.toml")
    catalog = Path.join(ctx.root, "codex/models.json")
    inputs = Map.merge(ctx.inputs, Map.new([config, catalog], &{&1, snapshot(&1)}))

    thread =
      call(ctx, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => Path.join(ctx.root, "workspace"),
        "baseInstructions" => @base,
        "historyMode" => "paginated",
        "ephemeral" => false
      })["thread"]["id"]

    assert is_binary(thread) and thread != ""

    assert call(ctx, pid, "thread/loaded/list", %{}) === %{
             "data" => [thread],
             "nextCursor" => nil
           }

    started = collect(pid, &notice?(&1, "thread/started", thread), deadline())
    assert notice?(started, "thread/started", thread)
    assert rows(ctx, "model_request") === [] and rows(ctx, "feedback_consumed") === []

    turn =
      call(ctx, pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => @marker}]
      })["turn"]["id"]

    events = collect(pid, &completed?(&1, thread, turn), deadline())
    assert_turn(events, thread, turn)

    saved =
      call(ctx, pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

    assert saved["id"] === thread

    assert [%{"id" => ^turn, "status" => "completed"}] =
             Enum.map(saved["turns"], &Map.take(&1, ~w(id status)))

    assert_provider(ctx, thread, turn)
    rollout_path = Map.fetch!(saved, "path")
    rollout = snapshot(rollout_path)
    assert_persisted_context(rollout.bytes, thread, turn)

    reports =
      for {id, label} <- [{-1, "first λ"}, {"-1", "second 🙂"}] do
        params = %{
          "classification" => "bug",
          "reason" => @reason,
          "includeLogs" => false,
          "threadId" => thread,
          "tags" => %{"ordinary_case" => label, "turn_id" => turn}
        }

        wire = %{"id" => id, "method" => "feedback/upload", "params" => params}
        assert_request(wire)
        result = call(ctx, pid, wire)
        assert result === %{"threadId" => thread, "promptHash" => @prompt_hash}

        assert :ok =
                 Schema.validate(schema("v2/FeedbackUploadResponse.json"), result, max_depth: 8)

        count = if is_integer(id), do: 1, else: 2
        wait(fn -> length(rows(ctx, "feedback_response_sent")) === count end, deadline())
        assert length(rows(ctx, "feedback_consumed")) === count

        report =
          rows(ctx, "feedback_consumed") |> List.last() |> assert_report(thread, turn, label)

        assert snapshot(rollout_path) === rollout
        assert_inputs(inputs)
        report
      end

    assert length(Enum.uniq(reports)) === 2
    assert_inventory(ctx)
    assert_provider(ctx, thread, turn)
    assert rows(ctx, "fixture_error") === []
    assert rows(ctx, "unexpected_model_request") === []
    assert rows(ctx, "unexpected_feedback_request") === []
    assert File.ls!(Path.join(ctx.root, "workspace")) === []

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
    assert {:ok, remaining} = Session.drain(pid, 128)
    assert_events(remaining)
    assert {:ok, []} = Session.drain(pid, 128)
    close(ctx, native)
    assert_inputs(inputs)
    assert snapshot(rollout_path) === rollout
    assert_provider(ctx, thread, turn)
    assert length(rows(ctx, "feedback_consumed")) === 2
    assert length(rows(ctx, "feedback_response_sent")) === 2
    assert rows(ctx, "fixture_error") === []
  end

  defp assert_report(row, thread, turn, label) do
    raw = Map.fetch!(row, "raw")
    assert 0 < byte_size(raw) and byte_size(raw) <= 262_144
    assert row["size"] === byte_size(raw) and row["sha256"] === hash(raw)
    [header, item, remainder] = String.split(raw, "\n", parts: 3)
    envelope = JSON.decode!(header)
    item = JSON.decode!(item)
    assert item["type"] === "event"
    size = Map.fetch!(item, "length")
    assert is_integer(size) and size > 0 and size <= byte_size(remainder)
    <<payload::binary-size(size), trailing::binary>> = remainder
    assert trailing in ["", "\n"]
    report = JSON.decode!(payload)
    identity = String.replace(Map.fetch!(envelope, "event_id"), "-", "")
    assert identity =~ ~r/^[a-f0-9]{32}$/
    assert String.replace(Map.fetch!(report, "event_id"), "-", "") === identity

    assert Map.take(
             Map.fetch!(report, "tags"),
             ~w(classification reason thread_id prompt_hash model turn_id ordinary_case)
           ) === %{
             "classification" => "bug",
             "reason" => @reason,
             "thread_id" => thread,
             "prompt_hash" => @prompt_hash,
             "model" => "mock-model",
             "turn_id" => turn,
             "ordinary_case" => label
           }

    assert report["message"] === "[Bug]: Codex session #{thread}"

    assert [%{"value" => @reason}] =
             Enum.map(report["exception"]["values"], &Map.take(&1, ["value"]))

    identity
  end

  defp assert_persisted_context(bytes, thread, turn) do
    lines = String.split(bytes, "\n", trim: true)
    assert length(lines) <= 128
    records = Enum.map(lines, &JSON.decode!/1)
    assert [metadata] = for(row <- records, row["type"] === "session_meta", do: row["payload"])

    assert Map.take(metadata, ["id", "base_instructions"]) === %{
             "id" => thread,
             "base_instructions" => %{"text" => @base, "provenance" => %{"type" => "custom"}}
           }

    assert [context] = for(row <- records, row["type"] === "turn_context", do: row["payload"])
    assert Map.take(context, ~w(turn_id model)) === %{"turn_id" => turn, "model" => "mock-model"}
  end

  defp assert_provider(ctx, thread, turn) do
    assert [row] = rows(ctx, "model_request")
    assert row["sequence"] === 1
    request = Map.fetch!(row, "request")
    assert JSON.decode!(row["raw"]) === request
    assert request["model"] === "mock-model"

    base_fragments =
      for item <- request["input"],
          item["role"] === "developer",
          part <- item["content"] || [],
          part["type"] === "input_text",
          part["text"] === @base,
          do: part["text"]

    assert base_fragments === [@base]
    metadata = JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

    assert Map.take(metadata, ~w(thread_id turn_id)) === %{
             "thread_id" => thread,
             "turn_id" => turn
           }

    text =
      for item <- request["input"],
          item["role"] === "user",
          part <- item["content"] || [],
          part["type"] === "input_text",
          do: part["text"]

    assert Enum.count(text, &(&1 === @marker)) === 1

    assert [%{"sequence" => 1}] =
             Enum.map(rows(ctx, "model_response_sent"), &Map.take(&1, ["sequence"]))
  end

  defp assert_turn(events, thread, turn) do
    assert completed?(events, thread, turn)

    assert [%{"text" => @answer}] =
             for(
               event <- events,
               event.wire["method"] === "item/completed",
               event.wire["params"]["threadId"] === thread,
               event.wire["params"]["turnId"] === turn,
               event.wire["params"]["item"]["type"] === "agentMessage",
               do: Map.take(event.wire["params"]["item"], ["text"])
             )
  end

  defp assert_request(wire) do
    document = schema("ClientRequest.json")

    owner =
      Enum.find(
        document["oneOf"],
        &(&1["properties"]["method"]["enum"] === ["feedback/upload"])
      )

    assert owner["properties"]["method"]["enum"] === ["feedback/upload"]
    assert owner["properties"]["params"] === %{"$ref" => "#/definitions/FeedbackUploadParams"}
    assert owner["required"] === ["id", "method", "params"]

    selected =
      Map.put(
        owner,
        "definitions",
        Map.take(document["definitions"], ~w(RequestId FeedbackUploadParams))
      )

    assert :ok = Schema.validate(selected, wire, max_depth: 16)

    assert :ok =
             Schema.validate(schema("v2/FeedbackUploadParams.json"), wire["params"], max_depth: 8)
  end

  defp start(ctx) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 128,
               max_event_bytes: 2_097_152,
               max_message_bytes: 262_144,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: System.find_executable("python3"),
                    args: [@script, "--root", ctx.root, "--codex", ctx.binary],
                    cwd: Path.join(ctx.root, "workspace"),
                    inherit_env: [],
                    max_message_bytes: 262_144,
                    env: %{
                      "HOME" => Path.join(ctx.root, "home"),
                      "CODEX_HOME" => Path.join(ctx.root, "codex"),
                      "TMPDIR" => Path.join(ctx.root, "tmp"),
                      "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
                      "PYTHONDONTWRITEBYTECODE" => "1"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)

    on_exit(fn ->
      try do
        request_close(ctx)
      after
        StdioSessionFixture.close(pid, connection)
      end

      assert_shutdown(ctx, %{connection: connection})
    end)

    id = request_id()
    info = %{"name" => "owned_ordinary_feedback", "version" => "0.1.0"}
    capabilities = %{"experimentalApi" => true}

    wire = %{
      "id" => id,
      "method" => "initialize",
      "params" => %{"clientInfo" => info, "capabilities" => capabilities}
    }

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id)

    assert_exchange(ctx, wire, response)
    assert [%{"pid" => native}] = rows(ctx, "native_started")
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    %{pid: pid, connection: connection, native: native}
  end

  defp call(ctx, pid, method, params),
    do: call(ctx, pid, %{"id" => request_id(), "method" => method, "params" => params})

  defp call(ctx, pid, wire) do
    id = wire["id"]

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire)

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
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp assert_inventory(ctx) do
    outgoing = frames(ctx, :out)

    assert Enum.map(outgoing, & &1.wire["method"]) ===
             ~w(initialize initialized thread/start thread/loaded/list turn/start thread/read feedback/upload feedback/upload)

    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))

    responses =
      Enum.filter(
        frames(ctx, :in),
        &(Map.has_key?(&1.wire, "id") and not Map.has_key?(&1.wire, "method"))
      )

    ids = Enum.map(requests, & &1.wire["id"])
    assert length(requests) === 7 and length(responses) === 7
    assert length(Enum.uniq(ids)) === 7
    assert MapSet.new(Enum.map(responses, & &1.wire["id"])) === MapSet.new(ids)

    assert Enum.map(
             Enum.filter(requests, &(&1.wire["method"] === "feedback/upload")),
             & &1.wire["id"]
           ) === [-1, "-1"]
  end

  defp frames(ctx, direction),
    do:
      Agent.get(
        ctx.capture,
        &Enum.filter(&1.frames, fn frame -> frame.direction === direction end)
      )

  defp notice?(events, "thread/started", thread),
    do:
      Enum.any?(
        events,
        &(&1.wire["method"] === "thread/started" and &1.wire["params"]["thread"]["id"] === thread)
      )

  defp completed?(events, thread, turn),
    do:
      Enum.any?(
        events,
        &(&1.wire["method"] === "turn/completed" and &1.wire["params"]["threadId"] === thread and
            &1.wire["params"]["turn"]["id"] === turn and
            &1.wire["params"]["turn"]["status"] === "completed")
      )

  defp collect(pid, events \\ [], ready, until) do
    assert {:ok, incoming} = Session.drain(pid, 128)
    events = events ++ incoming
    assert length(events) <= 128 and byte_size(:erlang.term_to_binary(events)) <= 2_097_152
    assert_events(events)

    if ready.(events) do
      events
    else
      assert System.monotonic_time(:millisecond) < until,
             "Ordinary feedback native event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Ordinary feedback event gap")
      after
        10 -> :ok
      end

      collect(pid, events, ready, until)
    end
  end

  defp assert_events(events) do
    refute Enum.any?(
             events,
             &(&1.kind in [:server_request, :unsupported_server_request] or
                 &1.wire["method"] === "error")
           )
  end

  defp close(ctx, native) do
    request_close(ctx)
    monitor = Process.monitor(native.connection.owner.pid)
    assert :ok = Session.close(native.pid)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert_shutdown(ctx, native)
  end

  defp request_close(ctx) do
    if rows(ctx, "native_closed") === [] do
      path = Path.join(ctx.root, "ordinary-feedback-close.json")

      if not File.exists?(path) do
        pending = path <> ".pending"
        File.write!(pending, JSON.encode!(%{"action" => "close"}), [:exclusive])
        File.rename!(pending, path)
      end

      wait(
        fn -> rows(ctx, "fixture_closed") != [] and rows(ctx, "native_closed") != [] end,
        deadline()
      )
    end
  end

  defp assert_shutdown(ctx, native) do
    assert :atomics.get(native.connection.owner.completion, 1) === 1
    assert Port.info(native.connection.port) === nil
    assert [%{"pid" => child}] = rows(ctx, "native_started")
    wait(fn -> not File.exists?("/proc/#{child}") end, deadline())
    assert [%{"pid" => controller, "namespace_owner_pid" => owner}] = rows(ctx, "fixture_started")

    wait(
      fn -> not File.exists?("/proc/#{controller}") and not File.exists?("/proc/#{owner}") end,
      deadline()
    )

    assert [%{}] = rows(ctx, "fixture_closed")
    assert [%{}] = rows(ctx, "native_closed")
    assert [%{}] = rows(ctx, "close_started")
  end

  defp rows(ctx, kind) do
    path = Path.join(ctx.root, "ordinary-feedback-journal.json")

    if File.exists?(path) do
      journal = snapshot(path, 3_145_728).bytes |> JSON.decode!()
      assert length(journal["events"]) <= 64
      Enum.filter(journal["events"], &(&1["event"] === kind))
    else
      []
    end
  end

  defp wait(predicate, until) do
    if predicate.() do
      :ok
    else
      assert System.monotonic_time(:millisecond) < until, "Ordinary feedback observation deadline"

      receive do
      after
        10 -> :ok
      end

      wait(predicate, until)
    end
  end

  defp assert_inputs(inputs),
    do: Enum.each(inputs, fn {path, original} -> assert(snapshot(path) === original) end)

  defp snapshot(path, limit \\ 1_048_576) do
    assert File.stat!(path).size <= limit
    bytes = File.read!(path)
    assert byte_size(bytes) <= limit
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp schema(name), do: name |> schema_path() |> File.read!() |> JSON.decode!()

  defp schema_path(name),
    do:
      :samgita_protocol_codex |> :code.priv_dir() |> Path.join("upstream/0.163.0/stable/" <> name)

  defp request_id, do: "ordinary-feedback-#{System.unique_integer([:positive, :monotonic])}"
  defp deadline, do: System.monotonic_time(:millisecond) + 5_000
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
