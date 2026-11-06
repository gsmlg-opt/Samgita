defmodule SamgitaCodexDriver.CompatibleSchemaTest do
  use ExUnit.Case, async: true

  alias SamgitaCodexDriver.{ScriptedTransport, Session}
  alias SamgitaProtocolCodex.{Error, Schema}

  defmodule RawTransport do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    import Kernel, except: [send: 2]

    @impl true
    defdelegate open(opts), to: ScriptedTransport
    @impl true
    defdelegate send(state, body), to: ScriptedTransport
    @impl true
    defdelegate close(state), to: ScriptedTransport
    @impl true
    defdelegate metadata(state), to: ScriptedTransport

    @impl true
    def handle_info({:incoming_raw, body}, state), do: {:ok, [{:message, body}], state}
    def handle_info(message, state), do: ScriptedTransport.handle_info(message, state)
  end

  test "invalid schema modes fail before opening any transport" do
    observer = self()

    for mode <- [:permissive, "compatible", nil] do
      attempt =
        Task.async(fn ->
          Process.flag(:trap_exit, true)

          Session.start_link(
            owner: observer,
            schema_mode: mode,
            transport: {ScriptedTransport, observer: observer}
          )
        end)

      assert {:error, %Error{code: :invalid_options}} = Task.await(attempt)

      refute_receive {:transport_opened, _}
    end
  end

  test "compatible mode returns drift as an unvalidated query outcome and stays usable" do
    pid = ready()
    wire = %{"id" => "drift", "result" => %{"data" => "future-shape"}, "extra" => [nil, 7]}
    call = request(pid, "thread/list", "drift")
    send(pid, {:incoming, wire})
    assert_unvalidated(Task.await(call), wire, false)
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, gap: nil} = Session.status(pid)
    assert_usable(pid)
  end

  test "omitted schema mode follows the configured default" do
    pid = ready(use_default_schema_mode: true)
    call = request(pid, "thread/list", "default")
    wire = %{"id" => "default", "result" => %{"data" => false}}
    send(pid, {:incoming, wire})
    outcome = Task.await(call)

    if Application.get_env(:samgita_codex_driver, :schema_mode, :compatible) == :compatible do
      assert_unvalidated(outcome, wire, false)
      assert Session.status(pid).phase == :ready
    else
      assert {:error, %Error{}} = outcome
      assert Session.status(pid).phase == :disconnected
    end
  end

  test "a drifted mutation retains uncertainty without settling another typed request ID" do
    pid = ready(schema_mode: :compatible)
    mutation = request(pid, "thread/start", 1)
    query = request(pid, "thread/list", "1")
    wire = %{"id" => 1, "result" => %{"futureThread" => %{}}}
    send(pid, {:incoming, wire})
    assert_unvalidated(Task.await(mutation), wire, true)
    assert [%{id: 1, method: "thread/start"}] = Session.uncertain_operations(pid)
    assert %{phase: :ready, pending: 1} = Session.status(pid)
    assert Task.yield(query, 0) == nil
    result = %{"id" => "1", "result" => %{"data" => []}}
    send(pid, {:incoming, result})
    assert {:ok, ^result} = Task.await(query)
    refute_receive {:sent, ^pid, %{"id" => 1}}
  end

  test "new fields accepted by the pinned schema retain the successful raw result" do
    for mode <- [:compatible, :strict] do
      pid = ready(schema_mode: mode)
      call = request(pid, "thread/list", "new-fields")

      wire = %{
        "id" => "new-fields",
        "result" => %{"data" => [], "newField" => %{"nullable" => nil}},
        "futureEnvelope" => [1, "two"]
      }

      send(pid, {:incoming, wire})
      assert {:ok, ^wire} = Task.await(call)
      assert Session.status(pid).phase == :ready
    end
  end

  test "a newly introduced result enum value remains intact but is never validated success" do
    pid = ready()

    thread = %{
      "id" => "thread",
      "sessionId" => "session",
      "projectId" => nil,
      "cliVersion" => "0.163.0",
      "createdAt" => 1,
      "updatedAt" => 1,
      "cwd" => "/isolated",
      "ephemeral" => false,
      "modelProvider" => "synthetic",
      "preview" => "",
      "source" => "cli",
      "status" => %{"type" => "active", "activeFlags" => []},
      "turns" => []
    }

    result = %{"data" => [thread], "nextCursor" => nil}
    assert :ok = Schema.validate_result(:server_response, "thread/list", result)
    future_thread = put_in(thread, ["status", "activeFlags"], ["futureActivity"])
    result = %{result | "data" => [future_thread]}

    assert {:error, %Error{code: :schema_violation}} =
             Schema.validate_result(:server_response, "thread/list", result)

    call = request(pid, "thread/list", "enum")
    wire = %{"id" => "enum", "result" => result}
    send(pid, {:incoming, wire})
    assert_unvalidated(Task.await(call), wire, false)
    assert_usable(pid)
  end

  test "wire-only outbound validation never treats a known drifted result as validated" do
    pid = ready()
    call = request(pid, "thread/list", "wire-known", validation: :wire)
    wire = %{"id" => "wire-known", "result" => %{"data" => 12}}
    send(pid, {:incoming, wire})
    assert_unvalidated(Task.await(call), wire, false)
    assert_usable(pid)
  end

  test "an explicit extension request retains an unvalidated result and mutation uncertainty" do
    pid = ready()
    call = request(pid, "future/read", "extension", validation: :wire)
    wire = %{"id" => "extension", "result" => %{"future" => nil}}
    send(pid, {:incoming, wire})
    assert_unvalidated(Task.await(call), wire, true)
    assert [%{id: "extension", method: "future/read"}] = Session.uncertain_operations(pid)
    assert Session.status(pid).phase == :ready
  end

  test "strict mode rejects known drift even when outbound validation is wire-only" do
    for options <- [[], [validation: :wire]] do
      pid = ready(schema_mode: :strict)
      call = request(pid, "thread/list", "strict", options)
      send(pid, {:incoming, %{"id" => "strict", "result" => %{"data" => false}}})
      assert {:error, %Error{}} = Task.await(call)
      assert %{phase: :disconnected, gap: %{}} = Session.status(pid)
    end
  end

  test "strict mode rejects an untyped extension response" do
    pid = ready(schema_mode: :strict)
    call = request(pid, "future/read", "strict-extension", validation: :wire)
    send(pid, {:incoming, %{"id" => "strict-extension", "result" => %{}}})
    assert {:error, %Error{uncertain: true}} = Task.await(call)
    assert Session.status(pid).phase == :disconnected
  end

  test "initialization drift never sends initialized or allows retry without reconnect" do
    pid = connection()
    call = Task.async(fn -> Session.initialize(pid, info(), %{}, id: "drift-init") end)
    assert_receive {:sent, ^pid, %{"id" => "drift-init", "method" => "initialize"}}, 2_000
    wire = %{"id" => "drift-init", "result" => %{"userAgent" => 7}}
    send(pid, {:incoming, wire})
    assert_unvalidated(Task.await(call), wire, false)
    assert Session.status(pid).phase == :initialization_failed
    refute_receive {:sent, ^pid, %{"method" => "initialized"}}
    assert {:error, %Error{code: :invalid_initialization_state}} = Session.initialize(pid, info())
    assert {:error, %Error{code: :not_initialized}} = Session.request(pid, "thread/list")
    assert :ok = Session.reconnect(pid)
    initialize(pid)
    assert_usable(pid)
  end

  test "new notification enum values and union variants remain observable and unvalidated" do
    pid = ready()

    for status <- [
          %{"type" => "futureState", "extension" => [nil]},
          %{"type" => "active", "activeFlags" => ["futureFlag"]}
        ] do
      wire = %{
        "method" => "thread/status/changed",
        "params" => %{"threadId" => "thread", "status" => status}
      }

      assert {:error, %Error{}} =
               Schema.validate_notification(:server_notification, wire["method"], wire["params"])

      event = receive_one(pid, wire)
      assert %{kind: :unvalidated_notification, wire: ^wire, validation: :unvalidated} = event
      assert_warning(event.warnings, :server_notification)
      assert Session.status(pid).phase == :ready
    end
  end

  test "wire-only initialization cannot bypass inbound readiness validation" do
    pid = connection()

    call =
      Task.async(fn ->
        Session.initialize(pid, info(), %{}, id: "wire-init", validation: :wire)
      end)

    assert_receive {:sent, ^pid, %{"id" => "wire-init", "method" => "initialize"}}, 2_000
    wire = %{"id" => "wire-init", "result" => %{}}
    send(pid, {:incoming, wire})
    assert_unvalidated(Task.await(call), wire, false)
    assert Session.status(pid).phase == :initialization_failed
    refute_receive {:sent, ^pid, %{"method" => "initialized"}}
  end

  test "known valid notifications with additional fields stay ordinary notifications" do
    pid = ready()

    wire = %{
      "method" => "thread/status/changed",
      "params" => %{"threadId" => "thread", "status" => %{"type" => "idle"}, "future" => nil}
    }

    assert %{kind: :notification, wire: ^wire} = receive_one(pid, wire)
  end

  test "unknown notifications remain visible in both modes with unvalidated metadata" do
    for mode <- [:compatible, :strict] do
      pid = ready(schema_mode: mode)
      wire = %{"method" => "future/event", "params" => %{"opaque" => [1, nil]}}
      event = receive_one(pid, wire)
      assert %{kind: :unknown_notification, wire: ^wire, validation: :unvalidated} = event
      assert_warning(event.warnings, :server_notification)
      assert Session.status(pid).phase == :ready
    end
  end

  test "strict known notification drift disconnects" do
    pid = ready(schema_mode: :strict)
    send(pid, {:incoming, %{"method" => "thread/status/changed", "params" => %{}}})
    assert %{phase: :disconnected, gap: %{}} = Session.status(pid)
    assert {:ok, []} = Session.drain(pid)
  end

  test "known invalid tool request is rejected without creating a response handle" do
    pid = ready()
    wire = put_in(tool("invalid"), ["params", "tool"], 7)
    send(pid, {:incoming, wire})
    assert_receive {:sent, ^pid, %{"id" => "invalid", "error" => %{"code" => -32_602}}}, 2_000
    assert {:ok, [event]} = Session.drain(pid)
    assert %{kind: :invalid_server_request, wire: ^wire, validation: :unvalidated} = event
    assert_warning(event.warnings, :server_request)
    refute Map.has_key?(event, :handle)
    assert %{phase: :ready, interactions: 0} = Session.status(pid)
    refute_receive {:sent, ^pid, %{"id" => "invalid", "result" => _}}
  end

  test "unknown tool request is rejected as unknown and never receives a response handle" do
    pid = ready()
    wire = %{"id" => "unknown", "method" => "future/tool", "params" => %{}}
    send(pid, {:incoming, wire})
    assert_receive {:sent, ^pid, %{"id" => "unknown", "error" => %{"code" => -32_601}}}, 2_000
    assert {:ok, [event]} = Session.drain(pid)
    assert %{kind: :unsupported_server_request, wire: ^wire} = event
    refute Map.has_key?(event, :handle)
    assert Session.status(pid).interactions == 0
  end

  test "strict invalid tool request disconnects instead of dispatching it" do
    pid = ready(schema_mode: :strict)
    send(pid, {:incoming, put_in(tool("strict-invalid"), ["params", "tool"], 7)})
    assert %{phase: :disconnected, interactions: 0} = Session.status(pid)
    assert {:ok, []} = Session.drain(pid)
    refute_receive {:sent, ^pid, %{"id" => "strict-invalid", "result" => _}}
  end

  test "unvalidated terminal notification cannot retire a live pure tool interaction" do
    pid = ready()
    assert %{kind: :server_request, handle: handle} = receive_one(pid, tool("tool-call"))

    wire = %{
      "method" => "turn/completed",
      "params" => %{
        "threadId" => "thread",
        "turn" => %{"id" => "turn", "status" => "futureTerminal", "items" => [], "error" => nil}
      }
    }

    assert %{kind: :unvalidated_notification, wire: ^wire} = receive_one(pid, wire)
    assert Session.status(pid).interactions == 1
    assert :ok = Session.respond(pid, handle, {:ok, %{"contentItems" => [], "success" => true}})
    assert_receive {:sent, ^pid, %{"id" => "tool-call", "result" => %{"success" => true}}}
  end

  test "drift events retain fixed warnings and remain subject to event count bounds" do
    pid = ready(max_events: 1)

    wire = %{
      "method" => "thread/status/changed",
      "params" => %{"status" => String.duplicate("x", 1000)}
    }

    send(pid, {:incoming, wire})
    assert_receive {:codex_driver, ^pid, :events_available}, 2_000
    send(pid, {:incoming, wire})
    assert %{phase: :disconnected, gap: %{reason: :event_buffer_overflow}} = Session.status(pid)
    assert {:ok, [event]} = Session.drain(pid)
    assert_warning(event.warnings, :server_notification)
    assert byte_size(:erlang.term_to_binary(event.warnings)) < 256
  end

  test "malformed envelopes still disconnect and outbound schema validation stays strict" do
    pid = ready()
    assert {:error, %Error{}} = Session.request(pid, "thread/read", %{"threadId" => 7})
    refute_receive {:sent, ^pid, %{"method" => "thread/read"}}
    assert Session.status(pid).phase == :ready
    send(pid, {:incoming, %{"id" => true, "result" => %{}}})
    assert %{phase: :disconnected, gap: %{}} = Session.status(pid)
  end

  test "validation warning metadata counts towards the existing event byte bound" do
    wire = %{"method" => "thread/status/changed", "params" => %{}}
    pid = ready(max_event_bytes: byte_size(JSON.encode!(wire)))
    send(pid, {:incoming, wire})
    assert %{phase: :disconnected, gap: %{reason: :event_buffer_overflow}} = Session.status(pid)
    assert {:ok, []} = Session.drain(pid)
  end

  test "malformed JSON, nesting and message size stay fatal in both schema modes" do
    nested = String.duplicate("[", 70) <> "0" <> String.duplicate("]", 70)

    oversized =
      JSON.encode!(%{"method" => "future/event", "params" => String.duplicate("x", 2048)})

    for mode <- [:compatible, :strict],
        {body, reason} <- [
          {"{", :invalid_json},
          {nested, :message_too_deep},
          {oversized, :message_too_large}
        ] do
      pid = ready(schema_mode: mode, raw_transport: true, max_message_bytes: 1024)
      pending = request(pid, "thread/start", "pending-mutation")
      send(pid, {:incoming_raw, body})
      assert {:error, %Error{code: ^reason, uncertain: true}} = Task.await(pending)
      assert %{phase: :disconnected, gap: %{reason: ^reason}} = Session.status(pid)
      assert [%{id: "pending-mutation"}] = Session.uncertain_operations(pid)
      assert {:ok, []} = Session.drain(pid)
    end
  end

  defp assert_unvalidated(outcome, wire, uncertain) do
    assert {:error,
            %Error{
              code: :unvalidated_response,
              wire: ^wire,
              uncertain: ^uncertain,
              details: %{validation: :unvalidated, warnings: warnings}
            }} = outcome

    assert_warning(warnings, :server_response)
  end

  defp assert_warning(warnings, direction) do
    assert [%{code: :schema_drift, direction: ^direction, reason: reason} = warning] = warnings
    assert is_atom(reason)
    assert map_size(warning) == 3
  end

  defp request(pid, method, id, opts \\ []) do
    task = Task.async(fn -> Session.request(pid, method, %{}, Keyword.put(opts, :id, id)) end)
    assert_receive {:sent, ^pid, %{"id" => ^id, "method" => ^method}}, 2_000
    task
  end

  defp assert_usable(pid) do
    id = "usable-#{System.unique_integer([:positive])}"
    call = request(pid, "thread/list", id)
    wire = %{"id" => id, "result" => %{"data" => []}}
    send(pid, {:incoming, wire})
    assert {:ok, ^wire} = Task.await(call)
  end

  defp receive_one(pid, wire) do
    send(pid, {:incoming, wire})
    assert_receive {:codex_driver, ^pid, :events_available}, 2_000
    assert {:ok, [event]} = Session.drain(pid)
    event
  end

  defp connection(opts \\ []) do
    {use_default, opts} = Keyword.pop(opts, :use_default_schema_mode, false)
    {raw_transport, opts} = Keyword.pop(opts, :raw_transport, false)
    transport = if raw_transport, do: RawTransport, else: ScriptedTransport
    opts = if use_default, do: opts, else: Keyword.put_new(opts, :schema_mode, :compatible)
    opts = Keyword.merge(opts, owner: self(), transport: {transport, observer: self()})
    pid = start_supervised!({Session, opts}, id: make_ref())
    assert_receive {:transport_opened, ^pid}
    pid
  end

  defp ready(opts \\ []) do
    pid = connection(opts)
    initialize(pid)
    pid
  end

  defp initialize(pid) do
    call = Task.async(fn -> Session.initialize(pid, info()) end)
    assert_receive {:sent, ^pid, %{"id" => id, "method" => "initialize"}}, 2_000

    result = %{
      "userAgent" => "codex/0.163.0",
      "codexHome" => "/isolated",
      "platformFamily" => "unix",
      "platformOs" => "linux"
    }

    send(pid, {:incoming, %{"id" => id, "result" => result}})
    assert {:ok, %{"result" => ^result}} = Task.await(call)
    assert_receive {:sent, ^pid, %{"method" => "initialized"}}, 2_000
  end

  defp info, do: %{"name" => "compatible_schema_test", "version" => "0.1.0"}

  defp tool(id) do
    %{
      "id" => id,
      "method" => "item/tool/call",
      "params" => %{
        "threadId" => "thread",
        "turnId" => "turn",
        "callId" => "item",
        "tool" => "pure_lookup",
        "arguments" => %{}
      }
    }
  end
end
