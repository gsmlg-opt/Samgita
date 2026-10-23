defmodule Samgita.CodexRuntimeNotificationTest.Transport do
  @moduledoc false
  @behaviour SamgitaCodexDriver.Transport

  def open(opts), do: {:ok, Map.new(opts)}

  def send(state, body) do
    Kernel.send(state.observer, {:native_sent, JSON.decode!(body)})

    if state.fail_send,
      do: {:error, SamgitaProtocolCodex.Error.new(:send_failed), state},
      else: {:ok, state}
  end

  def handle_info(_, _), do: :unknown
  def close(_), do: :ok
  def metadata(_), do: %{connected: true, transport: :synthetic_notification}
end

defmodule Samgita.CodexRuntimeNotificationTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures

  alias Samgita.{Agents, Attempts, CodexRuntime, Principal, Projects, Tasks}
  alias Samgita.CodexRuntime.{Driver, Native, Payload}

  alias Samgita.Domain.{
    CommandReceipt,
    DomainEvent,
    NativeRuntimeBinding,
    NativeRuntimeEvent,
    NativeRuntimeOperation,
    Project,
    Task,
    TaskAttempt
  }

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.Stdio

  setup tags do
    activate_fixture()
    pid = session(tags)
    project = project_fixture()
    agent = agent_fixture(%{"runtime_driver" => "codex", "runtime_version" => "0.163.0"})
    member_fixture(project, agent, ["worker"])
    {principal, _, _} = connection_fixture(agent)

    {:ok, execution_session} =
      Agents.open_session(
        principal,
        project["id"],
        command(%{"external_id" => Ecto.UUID.generate()})
      )

    {:ok, task} =
      Tasks.create(
        Principal.operator(),
        project["id"],
        command(%{"title" => "Notification proof"})
      )

    {:ok, attempt} =
      Attempts.claim(
        principal,
        project["id"],
        task["id"],
        command(%{"session_id" => execution_session["id"], "expected_version" => task["version"]})
      )

    {:ok, %{"proof" => proof}} = Attempts.proof(principal, project["id"], attempt["id"])

    {:ok, attempt} =
      Attempts.start(
        principal,
        project["id"],
        attempt["id"],
        command(%{"proof" => proof, "expected_version" => attempt["version"]})
      )

    {:ok, runtime} =
      CodexRuntime.bind(
        principal,
        project["id"],
        command(%{
          "proof" => proof,
          "expected_version" => attempt["version"],
          "attempt_id" => attempt["id"],
          "runtime_ref" => Ecto.UUID.generate(),
          "instance_id" => Session.status(pid).instance_id,
          "driver_generation" => 1
        })
      )

    %{
      pid: pid,
      principal: principal,
      project: project,
      runtime: runtime,
      proof: proof,
      task: task,
      attempt: attempt
    }
  end

  test "notification identity is local and idempotent without altering encrypted native envelopes",
       ctx do
    canary = "synthetic-notification-secret"

    for wire <- [
          %{"method" => "initialized"},
          %{"method" => "initialized", "params" => nil},
          %{"method" => "initialized", "params" => [nil, true, "é🙂"]},
          %{"method" => "initialized", "params" => 42, "future" => %{"value" => canary}}
        ] do
      attrs = native_attrs(ctx, wire)
      assert {:ok, operation} = prepare(ctx, attrs)
      assert {:ok, ^operation} = prepare(ctx, attrs)
      assert operation["direction"] == "client_notification"
      assert operation["effect"] == "read"
      stored = Repo.get!(NativeRuntimeOperation, operation["id"])
      runtime = Repo.get!(NativeRuntimeBinding, ctx.runtime["id"])

      assert {:ok, expected} =
               Payload.fingerprint(["client_notification", stored.id], runtime.fingerprint_key_id)

      assert stored.wire_id_digest == expected
      refute Jason.encode!(stored.request_payload) =~ canary
      assert {:ok, payload} = payload(ctx, operation)
      assert payload["request"] == wire
      refute Map.has_key?(payload["request"], "id")

      assert {:ok, other} = prepare(ctx, native_attrs(ctx, wire))
      refute other["id"] == operation["id"]
      refute Repo.get!(NativeRuntimeOperation, other["id"]).wire_id_digest == expected

      assert {:error, %{code: :conflict}} =
               prepare(ctx, Map.put(attrs, "native", Map.put(wire, "changed", true)))
    end

    assert Repo.aggregate(operations(ctx), :count) == 8

    for receipt <- Repo.all(CommandReceipt), do: refute(Jason.encode!(receipt.result) =~ canary)
    for event <- Repo.all(DomainEvent), do: refute(Jason.encode!(event.data) =~ canary)
  end

  test "platform accepts only pinned client notifications and enforces wire bounds", ctx do
    deep = Enum.reduce(1..65, nil, fn _, value -> [value] end)

    for wire <- [
          %{"method" => "future/notification"},
          %{"method" => "Initialized"},
          %{"method" => "initialized", "id" => nil},
          %{"method" => "initialized", "id" => "invented"},
          %{"id" => "invented", "result" => %{}},
          %{"method" => "initialized", "result" => nil},
          %{"method" => "initialized", "future" => %{atom_key: true}},
          %{"method" => "initialized", "future" => deep},
          %{"method" => "initialized", "future" => String.duplicate("x", 8_388_608)}
        ] do
      assert {:error, %{code: :invalid_native_payload}} =
               prepare(ctx, Map.put(native_attrs(ctx, wire), "validation", "wire"))
    end

    refute Repo.exists?(operations(ctx))
    refute_receive {:native_sent, _}
  end

  test "notification settlement accepts only unconfirmed or uncertain local sends with no response",
       ctx do
    for outcome <- ["sent_unconfirmed", "uncertain"] do
      {:ok, operation} = prepare(ctx, native_attrs(ctx))
      assert {:ok, ticket} = dispatch(ctx, operation)
      assert CodexRuntime.unresolved_effects?(ctx.attempt["id"])
      assert {:error, %{code: :stale_version}} = dispatch(ctx, operation)
      assert {:error, %{code: :conflict}} = dispatch(ctx, ticket)

      for invalid <- [
            %{"delivery_outcome" => "completed"},
            %{"delivery_outcome" => "native_error"},
            %{"delivery_outcome" => outcome, "native" => %{"id" => nil, "result" => %{}}},
            %{
              "delivery_outcome" => outcome,
              "native" => %{"id" => nil, "error" => %{"code" => 1, "message" => "invented"}}
            },
            %{"delivery_outcome" => outcome, "native" => %{"method" => "initialized"}}
          ] do
        assert {:error, %{code: :invalid_native_payload}} = settle(ctx, ticket, invalid)
        assert Repo.get!(NativeRuntimeOperation, ticket["id"]).state == "in_flight"
      end

      attrs = settlement_attrs(ticket, %{"delivery_outcome" => outcome, "native" => nil})
      assert {:ok, settled} = settle_attrs(ctx, ticket, attrs)
      assert settled["state"] == outcome
      assert settled["outcome_uncertain"]
      assert {:ok, ^settled} = settle_attrs(ctx, ticket, attrs)
      assert Repo.get!(NativeRuntimeOperation, ticket["id"]).response_payload == nil
      refute CodexRuntime.unresolved_effects?(ctx.attempt["id"])
    end

    assert_unchanged_execution(ctx)
  end

  test "logging-only effect classification is direction-specific and never clears other effects",
       ctx do
    assert Native.effect("initialized", "client_notification") == "read"
    assert Native.effect("initialized", "client_request") == "mutation"
    assert Native.effect("future/notification", "client_notification") == "mutation"
    assert Native.effect("thread/list", "client_notification") == "mutation"
    assert Native.effect("thread/list", "client_response") == "mutation"

    {:ok, mutation} =
      prepare(
        ctx,
        native_attrs(ctx, %{"id" => "mutation", "method" => "thread/start", "params" => %{}})
      )

    {:ok, ticket} = dispatch(ctx, mutation)
    assert {:ok, _} = settle(ctx, ticket, %{"delivery_outcome" => "uncertain"})
    assert CodexRuntime.unresolved_effects?(ctx.attempt["id"])
    {:ok, notification} = prepare(ctx, native_attrs(ctx))
    assert {:ok, %{"state" => "sent_unconfirmed"}} = execute(ctx, notification)
    assert_receive {:native_sent, %{"method" => "initialized"}}
    assert CodexRuntime.unresolved_effects?(ctx.attempt["id"])

    {:ok, next} =
      prepare(
        ctx,
        native_attrs(ctx, %{"id" => "next", "method" => "thread/start", "params" => %{}})
      )

    assert {:error, %{code: :uncertain_outcome}} = dispatch(ctx, next)
  end

  test "paused Projects permit logging-only notifications without permitting new mutation intents",
       ctx do
    {:ok, project} = Projects.get(Principal.operator(), ctx.project["id"])

    assert {:ok, _} =
             Projects.transition(
               Principal.operator(),
               project["id"],
               command(%{"expected_version" => project["version"], "state" => "paused"})
             )

    {:ok, notification} = prepare(ctx, native_attrs(ctx))
    assert {:ok, %{"state" => "sent_unconfirmed"}} = execute(ctx, notification)
    assert_receive {:native_sent, %{"method" => "initialized"}}

    assert {:error, %{code: :execution_closed}} =
             prepare(
               ctx,
               native_attrs(ctx, %{"id" => "paused", "method" => "thread/start", "params" => %{}})
             )

    assert Repo.get!(Project, project["id"]).state == "paused"
    assert_unchanged_execution(ctx)
  end

  test "notification settlement preserves a pre-existing observation gap", ctx do
    Repo.get!(NativeRuntimeBinding, ctx.runtime["id"])
    |> change(notification_gap: true)
    |> Repo.update!()

    {:ok, operation} = prepare(ctx, native_attrs(ctx))
    assert {:ok, %{"state" => "sent_unconfirmed"}} = execute(ctx, operation)
    assert_receive {:native_sent, %{"method" => "initialized"}}
    assert Repo.get!(NativeRuntimeBinding, ctx.runtime["id"]).notification_gap
    assert CodexRuntime.unresolved_effects?(ctx.attempt["id"])
    assert_unchanged_execution(ctx)
  end

  test "bridge rejects stale instance and generation before consuming a notification ticket",
       ctx do
    {:ok, operation} = prepare(ctx, native_attrs(ctx))
    runtime = Repo.get!(NativeRuntimeBinding, ctx.runtime["id"])
    Repo.update!(change(runtime, instance_id: Ecto.UUID.generate()))
    assert {:error, %{code: :ownership_lost}} = execute(ctx, operation)
    Repo.update!(change(runtime, instance_id: runtime.instance_id))
    assert :ok = Session.reconnect(ctx.pid)
    assert {:error, %{code: :ownership_lost}} = execute(ctx, operation)
    assert Repo.get!(NativeRuntimeOperation, operation["id"]).state == "prepared"
    refute_receive {:native_sent, _}
  end

  test "notification receipt replay and dispatch retain proof, lease and owner fences", ctx do
    attrs = native_attrs(ctx)
    {:ok, operation} = prepare(ctx, attrs)

    assert {:error, %{code: :ownership_lost}} =
             CodexRuntime.dispatch(
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               operation["id"],
               %{"proof" => "wrong", "expected_version" => operation["version"]}
             )

    assert {:error, %{code: :forbidden}} =
             CodexRuntime.prepare(
               Principal.operator(),
               ctx.project["id"],
               ctx.runtime["id"],
               attrs
             )

    Repo.get!(TaskAttempt, ctx.attempt["id"])
    |> change(lease_expires_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    assert {:error, %{code: :ownership_lost}} = prepare(ctx, attrs)
    assert {:error, %{code: :ownership_lost}} = dispatch(ctx, operation)
    assert Repo.get!(NativeRuntimeOperation, operation["id"]).state == "prepared"
    refute_receive {:native_sent, _}
  end

  test "bridge sends the complete notification once and never turns it into a response", ctx do
    wire = %{"method" => "initialized", "params" => nil, "future" => [true, "é🙂"]}
    {:ok, operation} = prepare(ctx, native_attrs(ctx, wire))
    before = Session.status(ctx.pid)
    assert {:ok, %{"state" => "sent_unconfirmed"} = settled} = execute(ctx, operation)
    assert_receive {:native_sent, ^wire}
    assert Session.status(ctx.pid) == before
    assert {:ok, payload} = payload(ctx, settled)
    assert payload["request"] == wire
    refute Map.has_key?(payload, "response")
    assert {:error, %{code: :conflict}} = execute(ctx, settled)
    assert :ok = Session.reconnect(ctx.pid)
    refute_receive {:native_sent, _}
    assert_unchanged_execution(ctx)
  end

  @tag fail_send: true
  test "failed notification send settles uncertain without storing the outgoing wire as a response",
       ctx do
    wire = %{"method" => "initialized", "future" => "failed-local-write"}
    {:ok, operation} = prepare(ctx, native_attrs(ctx, wire))
    assert {:ok, %{"state" => "uncertain"} = settled} = execute(ctx, operation)
    assert_receive {:native_sent, ^wire}
    assert_receive {:codex_driver, _, {:gap, %{reason: :send_failed}}}
    assert Session.status(ctx.pid).phase == :disconnected
    assert {:ok, payload} = payload(ctx, settled)
    assert payload["request"] == wire
    refute Map.has_key?(payload, "response")
    assert :ok = Session.reconnect(ctx.pid)
    refute_receive {:native_sent, _}
    assert_unchanged_execution(ctx)
  end

  @tag :real_codex
  @tag :e2e
  @tag timeout: 60_000
  test "pinned Codex receives explicit platform notifications with local-only journal settlement",
       ctx do
    assert Session.status(ctx.pid).phase == :new
    {:ok, early} = prepare(ctx, native_attrs(ctx))
    assert {:ok, %{"state" => "sent_unconfirmed"}} = execute(ctx, early)
    assert Session.status(ctx.pid).phase == :new

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(ctx.pid, %{
               "name" => "platform_notification_proof",
               "version" => "0.1.0"
             })

    for wire <- [
          %{"method" => "initialized", "params" => nil},
          %{"method" => "initialized", "params" => [nil, %{"text" => "é🙂"}], "future" => true},
          %{"method" => "initialized"}
        ] do
      {:ok, operation} = prepare(ctx, native_attrs(ctx, wire))
      assert {:ok, %{"state" => "sent_unconfirmed"} = settled} = execute(ctx, operation)
      assert {:ok, payload} = payload(ctx, settled)
      assert payload["request"] == wire
      refute Map.has_key?(payload, "response")

      assert {:ok, %{"result" => %{"data" => data}}} =
               Session.request(ctx.pid, "thread/list", %{})

      assert is_list(data)
      assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(ctx.pid)
      assert {:ok, events} = Session.drain(ctx.pid)
      assert Enum.all?(events, &(&1.kind == :notification))
      refute Enum.any?(events, &(&1.wire["method"] == "initialized"))
    end

    assert :ok = Session.close(ctx.pid)
    assert_unchanged_execution(ctx)
  end

  defp session(%{real_codex: true}) do
    binary = System.fetch_env!("CODEX_BINARY")

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) ==
             "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

    root = Path.join(System.tmp_dir!(), "samgita-platform-notify-#{Ecto.UUID.generate()}")
    home = Path.join(root, "home")
    codex_home = Path.join(root, "codex")
    workspace = Path.join(root, "workspace")
    Enum.each([home, codex_home, workspace], &File.mkdir_p!/1)
    on_exit(fn -> File.rm_rf!(root) end)

    pid =
      start_supervised!(
        {Session,
         [
           owner: self(),
           transport:
             {Stdio,
              [
                executable: binary,
                args: ["app-server", "--listen", "stdio://"],
                cwd: workspace,
                env: %{
                  "HOME" => home,
                  "CODEX_HOME" => codex_home,
                  "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                  "RUST_LOG" => "off"
                }
              ]}
         ]}
      )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> assert :ok = Stdio.close(connection) end)
    pid
  end

  defp session(tags),
    do:
      start_supervised!(
        {Session,
         [
           owner: self(),
           transport:
             {__MODULE__.Transport, [observer: self(), fail_send: tags[:fail_send] == true]}
         ]}
      )

  defp native_attrs(ctx, wire \\ %{"method" => "initialized"}) do
    runtime = Repo.get!(NativeRuntimeBinding, ctx.runtime["id"])
    command(%{"proof" => ctx.proof, "expected_version" => runtime.version, "native" => wire})
  end

  defp prepare(ctx, attrs),
    do: CodexRuntime.prepare(ctx.principal, ctx.project["id"], ctx.runtime["id"], attrs)

  defp dispatch(ctx, operation),
    do:
      CodexRuntime.dispatch(
        ctx.principal,
        ctx.project["id"],
        ctx.runtime["id"],
        operation["id"],
        %{"proof" => ctx.proof, "expected_version" => operation["version"]}
      )

  defp execute(ctx, operation),
    do:
      Driver.execute(
        ctx.pid,
        ctx.principal,
        ctx.project["id"],
        ctx.runtime["id"],
        operation["id"],
        %{"proof" => ctx.proof, "expected_version" => operation["version"]}
      )

  defp settlement_attrs(ticket, attrs),
    do:
      command(
        Map.merge(attrs, %{
          "expected_version" => ticket["version"],
          "dispatch_token" => ticket["dispatch_token"]
        })
      )

  defp settle(ctx, ticket, attrs), do: settle_attrs(ctx, ticket, settlement_attrs(ticket, attrs))

  defp settle_attrs(ctx, ticket, attrs),
    do:
      CodexRuntime.settle(
        ctx.principal,
        ctx.project["id"],
        ctx.runtime["id"],
        ticket["id"],
        attrs
      )

  defp payload(ctx, operation),
    do:
      CodexRuntime.native_operation(
        ctx.principal,
        ctx.project["id"],
        ctx.runtime["id"],
        operation["id"]
      )

  defp operations(ctx),
    do: from(o in NativeRuntimeOperation, where: o.runtime_id == ^ctx.runtime["id"])

  defp assert_unchanged_execution(ctx) do
    assert Repo.get!(Task, ctx.task["id"]).state == "in_progress"
    assert Repo.get!(TaskAttempt, ctx.attempt["id"]).state == "running"
    assert Repo.get!(NativeRuntimeBinding, ctx.runtime["id"]).source_sequence == 0
    refute Repo.exists?(from e in NativeRuntimeEvent, where: e.runtime_id == ^ctx.runtime["id"])

    assert {:ok, %{"links" => []}} =
             CodexRuntime.get(ctx.principal, ctx.project["id"], ctx.runtime["id"])
  end
end
