defmodule SamgitaCodexDriver.NativeOrdinaryMcpFormLifecycleTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaProtocolCodex.{Error, Schema}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_mcp_form_fixture.py", __DIR__)
  @script_sha "2f0eb4e91e42bd1c7d665c559ff4c5d39af61ed6a5d0d30f0bb8e3d3bcc142f3"
  @message "Choose an ordinary display label"
  @meta %{"fixture/request" => %{"topic" => "ordinary-label"}}
  @reply %{
    "action" => "accept",
    "content" => %{"label" => "Ordinary label λ🙂"},
    "_meta" => %{"fixture/response" => %{"topic" => "ordinary-label"}}
  }

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio

    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    def send(state, encoded) do
      wire = JSON.decode!(encoded)

      selected =
        wire["method"] in ["thread/start", "turn/start", "turn/interrupt"] or
          (Map.has_key?(wire, "result") and not Map.has_key?(wire, "method"))

      if selected do
        with :ok <- append(state, :out, encoded, wire), do: Stdio.send(state, encoded)
      else
        Stdio.send(state, encoded)
      end
    end

    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          result = Enum.reduce_while(events, :ok, &record_event(&1, &2, next))

          case result do
            :ok -> {:ok, events, next}
            {:error, error} -> {:error, error, next}
          end

        other ->
          other
      end
    end

    defp record_event({:message, encoded}, :ok, state) do
      wire = JSON.decode!(encoded)

      if wire["method"] in [
           "mcpServer/elicitation/request",
           "serverRequest/resolved",
           "turn/completed"
         ] do
        case append(state, :in, encoded, wire) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      else
        {:cont, :ok}
      end
    end

    defp record_event(_, :ok, _state), do: {:cont, :ok}

    defp append(state, direction, encoded, wire) do
      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(encoded)

        if length(ledger.frames) < 32 and size <= 65_536 and ledger.bytes + size <= 1_048_576 do
          {:ok,
           %{frames: ledger.frames ++ [{direction, encoded, wire}], bytes: ledger.bytes + size}}
        else
          {{:error, SamgitaProtocolCodex.Error.new(:test_capture_overflow)}, ledger}
        end
      end)
    end

    def close(state), do: Stdio.close(state)
    def metadata(state), do: Stdio.metadata(state)
  end

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) == @binary_sha
    assert hash(File.read!(@script)) == @script_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-ordinary-mcp-form-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "assistant")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    File.write!(fixture.requests, "[]")
    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)

    ctx = %{
      binary: binary,
      root: root,
      fixture: fixture,
      capture: start_supervised!({Agent, fn -> %{frames: [], bytes: 0} end})
    }

    TurnFixture.configure_model(ctx, %{})
    ctx
  end

  test "native ordinary Form carries an answer then retires an unanswered form on interruption",
       ctx do
    session = start(ctx)
    pid = session.pid

    started =
      call(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "ephemeral" => true,
        "threadSource" => "user"
      })

    assert started["thread"]["threadSource"] === "user"
    thread = started["thread"]["id"]
    assert is_binary(thread) and thread != ""
    assert ModelFixture.requests(ctx.fixture) == []

    first = turn(pid, thread, "Record an ordinary label")
    held = collect(ctx, pid, [], &has_request?/1, deadline())
    request = assert_request(ctx, held, thread, first)
    assert %{interactions: 1, pending: 0, gap: nil} = Session.status(pid)
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    assert peer_replies(ctx) == []
    assert :ok = Session.respond(pid, request.handle, {:ok, @reply})

    [{:out, sent_bytes, sent_wire}] =
      frames(ctx, &(Map.has_key?(&1, "result") and &1["id"] === request.wire["id"]))

    assert sent_wire === %{"id" => request.wire["id"], "result" => @reply}
    assert sent_bytes === JSON.encode!(sent_wire)

    answered =
      collect(
        ctx,
        pid,
        held,
        &(completed?(&1, first, "completed") and resolved?(&1, request)),
        deadline()
      )

    assert_request(ctx, answered, thread, first)
    assert_resolution(ctx, answered, request)

    assert [%{"item" => %{"text" => "Ordinary label recorded"}}] =
             notifications(answered, "item/completed", fn p ->
               p["turnId"] == first and p["item"]["type"] == "agentMessage"
             end)

    for {method, status} <- [{"item/started", "inProgress"}, {"item/completed", "completed"}] do
      assert [
               %{
                 "item" => %{
                   "server" => "fixture",
                   "tool" => "select_label",
                   "arguments" => %{},
                   "status" => ^status
                 }
               }
             ] =
               notifications(
                 answered,
                 method,
                 &(&1["turnId"] == first and &1["item"]["type"] == "mcpToolCall")
               )
    end

    [received] = peer_replies(ctx)
    assert received === %{"jsonrpc" => "2.0", "id" => "ordinary-label-form-1", "result" => @reply}
    [initial, continuation] = ModelFixture.requests(ctx.fixture)
    namespace = Enum.find(initial["tools"], &(&1["name"] == "mcp__fixture"))
    assert Enum.any?(namespace["tools"], &(&1["name"] == "select_label"))

    [output] =
      Enum.filter(
        continuation["input"],
        &(&1["type"] == "function_call_output" and &1["call_id"] == "ordinary-label-call-1")
      )

    assert [%{"type" => "input_text"}, %{"type" => "input_text", "text" => text}] =
             output["output"]

    assert JSON.decode!(text) === received
    [outcome] = outcomes = Session.interaction_outcomes(pid)
    assert outcome.handle === request.handle and outcome.status === :resolution_observed
    assert outcome.response_digest === hash(sent_bytes)
    assert %{interactions: 0} = Session.status(pid)

    assert {:error, %Error{code: :stale_interaction}} =
             Session.respond(pid, request.handle, {:ok, @reply})

    second = turn(pid, thread, "Leave the next ordinary label unanswered")
    held2 = collect(ctx, pid, [], &has_request?/1, deadline())
    interrupted_request = assert_request(ctx, held2, thread, second)
    refute interrupted_request.handle === request.handle
    assert %{interactions: 1} = Session.status(pid)
    assert length(ModelFixture.requests(ctx.fixture)) == 3
    assert peer_replies(ctx) === [received]
    before_interrupt = Agent.get(ctx.capture, & &1)
    assert call(pid, "turn/interrupt", %{"threadId" => thread, "turnId" => second}) == %{}

    interrupted =
      collect(
        ctx,
        pid,
        held2,
        &(completed?(&1, second, "interrupted") and resolved?(&1, interrupted_request)),
        deadline()
      )

    assert_request(ctx, interrupted, thread, second)
    assert_resolution(ctx, interrupted, interrupted_request)

    assert notifications(interrupted, "item/completed", &(&1["item"]["type"] == "agentMessage")) ==
             []

    wait_peer_cancel(ctx, deadline())

    assert peer_replies(ctx) === [
             received,
             %{
               "jsonrpc" => "2.0",
               "id" => "ordinary-label-form-2",
               "result" => %{"action" => "cancel"}
             }
           ]

    assert %{interactions: 0, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert Session.interaction_outcomes(pid) === outcomes

    before_late = Agent.get(ctx.capture, & &1)

    assert {:error, %Error{code: :stale_interaction}} =
             Session.respond(pid, interrupted_request.handle, {:ok, @reply})

    assert Agent.get(ctx.capture, & &1) === before_late

    assert Enum.filter(
             Enum.drop(before_late.frames, length(before_interrupt.frames)),
             &(elem(&1, 0) == :out)
           )
           |> Enum.map(fn {_, _, wire} -> wire["method"] end) == ["turn/interrupt"]

    [_, _, pending_provider] = ModelFixture.requests(ctx.fixture)
    assert_provider_turn(initial, thread, first)
    assert_provider_turn(continuation, thread, first)
    assert_provider_turn(pending_provider, thread, second)
    rows = journal(ctx)
    [peer] = for %{"kind" => "peer-start", "pid" => peer} <- rows, do: peer
    assert is_integer(peer) and peer != session.native and File.exists?("/proc/#{peer}")

    assert length(
             for %{"direction" => "in", "message" => %{"method" => "tools/call"}} <- rows,
                 do: :call
           ) == 2

    assert length(
             for %{"direction" => "out", "message" => %{"method" => "elicitation/create"}} <-
                   rows,
                 do: :form
           ) == 2

    close(session)
    refute File.exists?("/proc/#{peer}")
    assert length(ModelFixture.requests(ctx.fixture)) == 3

    assert peer_replies(ctx) === [
             received,
             %{
               "jsonrpc" => "2.0",
               "id" => "ordinary-label-form-2",
               "result" => %{"action" => "cancel"}
             }
           ]

    assert File.ls!(ctx.fixture.workspace) == []
    ledger = Agent.get(ctx.capture, & &1)
    assert ledger.bytes == Enum.sum(for {_, bytes, _} <- ledger.frames, do: byte_size(bytes))
    assert length(ledger.frames) == 11
    for {_direction, original, wire} <- ledger.frames, do: assert(JSON.decode!(original) === wire)
    assert :ok = ModelFixture.close(ctx.fixture)
    assert :atomics.get(ctx.fixture.transport.owner.completion, 1) == 1
    assert Port.info(ctx.fixture.port) == nil
  end

  defp assert_request(ctx, events, thread, turn) do
    [request] = Enum.filter(events, &(&1.kind == :server_request))
    assert request.wire["method"] == "mcpServer/elicitation/request"
    assert request.handle.id === request.wire["id"]
    params = request.wire["params"]

    assert params === %{
             "threadId" => thread,
             "turnId" => turn,
             "serverName" => "fixture",
             "mode" => "form",
             "message" => @message,
             "_meta" => @meta,
             "requestedSchema" => %{
               "type" => "object",
               "properties" => %{
                 "label" => %{
                   "type" => "string",
                   "title" => "Display label",
                   "description" => "Ordinary synthetic label",
                   "minLength" => 1,
                   "maxLength" => 64,
                   "default" => "Draft label"
                 }
               },
               "required" => ["label"]
             }
           }

    schema =
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/McpServerElicitationRequestParams.json")
      |> File.read!()
      |> JSON.decode!()

    ordinary_form = schema["oneOf"] |> Enum.at(1) |> Map.put("definitions", schema["definitions"])
    assert :ok = Schema.validate(ordinary_form, params, max_depth: 32)

    assert [{:in, bytes, wire}] =
             frames(
               ctx,
               &(&1["method"] == "mcpServer/elicitation/request" and
                   &1["id"] === request.wire["id"])
             )

    assert JSON.decode!(bytes) === wire and wire === request.wire
    request
  end

  defp assert_resolution(ctx, events, request) do
    [resolved] = Enum.filter(events, &(&1.wire["method"] == "serverRequest/resolved"))

    assert resolved.wire["params"] === %{
             "threadId" => request.wire["params"]["threadId"],
             "requestId" => request.wire["id"]
           }

    assert request.sequence < resolved.sequence

    assert [{:in, bytes, wire}] =
             frames(
               ctx,
               &(&1["method"] == "serverRequest/resolved" and
                   &1["params"]["requestId"] === request.wire["id"])
             )

    assert JSON.decode!(bytes) === wire and wire === resolved.wire
  end

  defp frames(ctx, predicate),
    do:
      Agent.get(ctx.capture, fn ledger ->
        Enum.filter(ledger.frames, fn {_, _, wire} -> predicate.(wire) end)
      end)

  defp has_request?(events), do: Enum.any?(events, &(&1.kind == :server_request))

  defp resolved?(events, request),
    do:
      Enum.any?(
        events,
        &(&1.wire["method"] == "serverRequest/resolved" and
            &1.wire["params"]["requestId"] === request.wire["id"])
      )

  defp completed?(events, turn, status),
    do:
      notifications(
        events,
        "turn/completed",
        &(&1["turn"]["id"] == turn and &1["turn"]["status"] == status)
      ) != []

  defp notifications(events, method, predicate),
    do:
      for(
        event <- events,
        event.wire["method"] == method,
        predicate.(event.wire["params"]),
        do: event.wire["params"]
      )

  defp turn(pid, thread, text),
    do:
      call(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [
          %{"type" => "text", "text" => text},
          %{"type" => "mention", "name" => "Fixture", "path" => "mcp://fixture"}
        ]
      })["turn"]["id"]

  defp collect(ctx, pid, events, ready, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256 and byte_size(:erlang.term_to_binary(events)) <= 1_048_576
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    refute Enum.any?(
             events,
             &(&1.wire["method"] == "error" or &1.kind == :unsupported_server_request)
           )

    if ready.(events) do
      events
    else
      tick(pid, until, fn -> failure_diagnostic(ctx, pid, events) end)
      collect(ctx, pid, events, ready, until)
    end
  end

  defp tick(pid, until, on_failure \\ fn -> :ok end) do
    within_deadline = System.monotonic_time(:millisecond) < until

    try do
      unless within_deadline, do: on_failure.()
    after
      assert within_deadline, "Native ordinary form observable deadline"
    end

    receive do
      {:codex_driver, ^pid, :events_available} -> :ok
      {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected ordinary form event gap")
    after
      10 -> :ok
    end
  end

  # Failure-only ordinary synthetic evidence survives fixture cleanup in the
  # parent-owned test log. It does not answer a request or extend any deadline.
  defp failure_diagnostic(ctx, pid, events) do
    providers =
      for request <- ModelFixture.requests(ctx.fixture) do
        %{
          "model" => request["model"],
          "tools" => Enum.map(request["tools"] || [], &tool_identity/1),
          "outputs" =>
            Enum.filter(request["input"] || [], &(&1["type"] == "function_call_output"))
        }
      end

    evidence = %{
      "events" =>
        Enum.map(events, fn event ->
          %{
            "kind" => Atom.to_string(event.kind),
            "sequence" => event.sequence,
            "wire" => event.wire
          }
        end),
      "provider" => providers,
      "peer" => journal(ctx),
      "phase" => Atom.to_string(Session.status(pid).phase)
    }

    encoded = JSON.encode!(evidence)
    assert byte_size(encoded) <= 3_145_728
    IO.puts("V539_ORDINARY_FORM_FAILURE " <> encoded)
  end

  defp tool_identity(tool) do
    identity = Map.take(tool, ~w(type name))

    if is_list(tool["tools"]),
      do: Map.put(identity, "tools", Enum.map(tool["tools"], &Map.take(&1, ~w(type name)))),
      else: identity
  end

  defp wait_peer_cancel(ctx, until) do
    rows = journal(ctx)

    [_, call] =
      for %{"direction" => "in", "message" => %{"method" => "tools/call"} = message} <- rows,
          do: message

    finished =
      Enum.any?(rows, fn row ->
        row["direction"] == "out" and row["message"]["id"] === call["id"] and
          Map.has_key?(row["message"], "result")
      end)

    if length(peer_replies(ctx)) < 2 or not finished do
      tick(nil, until)
      wait_peer_cancel(ctx, until)
    end
  end

  defp journal(ctx) do
    path = Path.join(ctx.fixture.codex_home, "ordinary-mcp-form.jsonl")

    case File.read(path) do
      {:ok, bytes} ->
        assert byte_size(bytes) <= 1_048_576
        rows = bytes |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
        assert length(rows) <= 64
        rows

      {:error, :enoent} ->
        []
    end
  end

  defp peer_replies(ctx),
    do:
      for(
        %{"direction" => "in", "message" => message} <- journal(ctx),
        message["id"] in ["ordinary-label-form-1", "ordinary-label-form-2"],
        do: message
      )

  defp assert_provider_turn(request, thread, turn) do
    assert request["model"] == "mock-model"

    assert request["client_metadata"]["x-codex-turn-metadata"]
           |> JSON.decode!()
           |> Map.take(~w(thread_id turn_id)) == %{"thread_id" => thread, "turn_id" => turn}
  end

  defp call(pid, method, params) do
    id = "ordinary-form-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, %{"id" => id, "method" => method, "params" => params},
               timeout_ms: 5_000
             )

    assert byte_size(JSON.encode!(response)) <= 65_536
    result
  end

  defp start(ctx) do
    assert {:ok, pid} =
             Session.start_link(
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    env: %{
                      "HOME" => ctx.fixture.home,
                      "CODEX_HOME" => ctx.fixture.codex_home,
                      "TMPDIR" => ctx.root,
                      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                      "RUST_LOG" => "off",
                      "NO_COLOR" => "1"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "ordinary_mcp_form", "version" => "0.1.0"},
               %{
                 "experimentalApi" => true,
                 "extensions" => %{"openai/standard-form-input" => %{}}
               },
               timeout_ms: 5_000
             )

    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    %{pid: pid, native: native, connection: connection}
  end

  defp close(session) do
    assert :ok = Session.close(session.pid)
    assert :atomics.get(session.connection.owner.completion, 1) == 1
    assert Port.info(session.connection.port) == nil
    refute File.exists?("/proc/#{session.native}")
  end

  defp deadline, do: System.monotonic_time(:millisecond) + 20_000
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
