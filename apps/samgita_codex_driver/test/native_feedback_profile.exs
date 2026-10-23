defmodule SamgitaCodexDriver.NativeFeedbackProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag :isolated_feedback
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_feedback_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @reason "Owned synthetic feedback only."
  @filename "owned-feedback-diagnostic.txt"
  @attachment "Owned synthetic diagnostic only.\n"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert digest(File.read!(binary)) == @sha
    for tool <- ~w(python3 unshare ip openssl), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-feedback-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    File.mkdir!(root)

    for directory <- ~w(home codex workspace tmp), do: File.mkdir_p!(Path.join(root, directory))
    ctx = %{root: root, binary: Path.expand(binary), scenario: tags[:scenario]}

    on_exit(fn ->
      if File.exists?(Path.join(root, "journal.json")) do
        for started <- events(ctx, "native_started"),
            key <- ~w(pid controller_pid namespace_owner_pid),
            do: wait(fn -> not File.exists?("/proc/#{started[key]}") end)

        if events(ctx, "native_started") != [] do
          assert events(ctx, "peer_closed") != []
          assert events(ctx, "native_closed") != []
        end
      end

      File.rm_rf!(root)
    end)

    ctx
  end

  @tag scenario: "event"
  test "actual native event-only feedback returns HTTP acceptance with generated thread identity",
       ctx do
    pid = start(ctx)
    result = upload(pid, params(ctx))
    assert result["threadId"] =~ ~r/^no-active-thread-[a-f0-9-]{36}$/
    assert result["promptHash"] == nil
    assert Map.keys(result) |> Enum.sort() == ["promptHash", "threadId"]

    assert [%{"kind" => "event", "status" => 200} = event] = uploads(ctx)
    assert event["thread_id"] == result["threadId"]
    wait(fn -> length(events(ctx, "response_sent")) == 1 end)
    assert length(events(ctx, "response_sent")) == 1
    finish(ctx, pid)
  end

  @tag scenario: "extra"
  test "includeLogs false uploads only an explicitly owned file after the core event", ctx do
    pid = start(ctx)
    result = upload(pid, params(ctx))
    assert result["promptHash"] == nil

    assert [
             %{"kind" => "event", "status" => 200} = event,
             %{"kind" => "attachment", "status" => 200} = attachment
           ] = uploads(ctx)

    assert event["thread_id"] == result["threadId"]
    assert attachment["event_id"] == event["event_id"]
    assert attachment["filename"] == @filename
    assert attachment["decoded_size"] == byte_size(@attachment)
    assert attachment["payload_sha256"] == digest(@attachment)
    wait(fn -> length(events(ctx, "response_sent")) == 2 end)
    assert length(events(ctx, "response_sent")) == 2
    finish(ctx, pid)
  end

  for status <- [429, 503] do
    @tag scenario: "core#{status}"
    test "core HTTP #{status} stays a native failure and never replays the core", ctx do
      pid = start(ctx)
      failure = upload_error(pid, params(ctx))
      assert failure["code"] == -32_603
      assert failure["message"] =~ "failed to upload feedback:"
      assert failure["message"] =~ "Sentry rejected feedback upload with HTTP status"
      assert failure["message"] =~ "#{unquote(status)}"
      assert [%{"kind" => "event", "status" => unquote(status)}] = uploads(ctx)
      wait(fn -> length(events(ctx, "response_sent")) == 1 end)
      assert length(events(ctx, "response_sent")) == 1
      finish(ctx, pid)
    end
  end

  @tag scenario: "partial"
  test "accepted core and exhausted attachment retries retain explicit partial acceptance", ctx do
    pid = start(ctx)
    failure = upload_error(pid, params(ctx))
    assert failure["code"] == -32_603

    assert failure["message"] =~
             "feedback report was accepted, but some attachments failed to upload"

    assert [%{"kind" => "event", "status" => 200} = core | attachments] = uploads(ctx)
    assert length(attachments) == 3

    for attachment <- attachments do
      assert attachment["kind"] == "attachment" and attachment["status"] == 503
      assert attachment["event_id"] == core["event_id"]
      assert attachment["filename"] == @filename
      assert attachment["payload_sha256"] == digest(@attachment)
    end

    wait(fn -> length(events(ctx, "response_sent")) == 4 end)
    assert length(events(ctx, "response_sent")) == 4

    assert length(
             events(ctx, "native_input")
             |> Enum.filter(&(&1["method"] == "feedback/upload"))
           ) == 1

    finish(ctx, pid)
  end

  @tag scenario: "held"
  test "three observed held uploads reject overload and release capacity without replay", ctx do
    pid = start(ctx)

    pending =
      for _ <- 1..3 do
        Task.async(fn -> upload_error(pid, params(ctx)) end)
      end

    wait(fn -> length(uploads(ctx)) == 3 end)
    assert events(ctx, "response_sent") == []

    assert upload_error(pid, params(ctx)) == %{
             "code" => -32_001,
             "message" =>
               "Three feedback uploads are already in progress; try again after one finishes"
           }

    assert length(uploads(ctx)) == 3
    File.write!(Path.join(ctx.root, "release-response"), "release owned synthetic responses")

    for task <- pending do
      failure = Task.await(task, 5_000)
      assert failure["code"] == -32_603
      assert failure["message"] =~ "failed to upload feedback:"
    end

    assert upload_error(pid, params(ctx))["code"] == -32_603
    assert length(uploads(ctx)) == 4
    assert length(Enum.uniq_by(uploads(ctx), & &1["event_id"])) == 4
    assert Enum.all?(uploads(ctx), &(&1["kind"] == "event" and &1["status"] == 503))
    wait(fn -> length(events(ctx, "response_sent")) == 4 end)
    assert length(events(ctx, "response_sent")) == 4
    finish(ctx, pid)
  end

  defp start(ctx) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: System.find_executable("python3"),
             args: [
               @script,
               "--root",
               ctx.root,
               "--codex",
               ctx.binary,
               "--scenario",
               ctx.scenario
             ],
             cwd: Path.join(ctx.root, "workspace"),
             inherit_env: [],
             env: %{
               "HOME" => Path.join(ctx.root, "home"),
               "CODEX_HOME" => Path.join(ctx.root, "codex"),
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
               "PYTHONDONTWRITEBYTECODE" => "1"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(pid, %{"name" => "samgita_feedback", "version" => "1"})

    wait(fn -> Enum.any?(events(ctx, "native_input"), &(&1["method"] == "initialized")) end)
    pid
  end

  defp params(ctx) do
    params = %{"classification" => "bug", "reason" => @reason, "includeLogs" => false}

    if ctx.scenario in ["extra", "partial"],
      do: Map.put(params, "extraLogFiles", [Path.join(ctx.root, @filename)]),
      else: params
  end

  defp upload(pid, params) do
    id = "owned-feedback-#{System.unique_integer([:positive])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, "feedback/upload", params, id: id)

    result
  end

  defp upload_error(pid, params) do
    id = "owned-feedback-error-#{System.unique_integer([:positive])}"

    assert {:error, %Error{code: :upstream_error, wire: %{"id" => ^id, "error" => failure}}} =
             Session.request(pid, "feedback/upload", params, id: id)

    failure
  end

  defp finish(ctx, pid) do
    assert {:ok, %{"result" => %{"data" => [], "nextCursor" => nil}}} =
             Session.request(pid, "thread/loaded/list", %{})

    assert Session.status(pid).phase == :ready
    assert Session.status(pid).interactions == 0
    assert {:ok, received} = Session.drain(pid)

    assert Enum.all?(
             received,
             &(&1.kind != :server_request and &1.wire["method"] != "turn/started")
           )

    assert Session.uncertain_operations(pid) == []

    proof = journal(ctx)["namespace"]
    assert proof["parent"] == File.read_link!("/proc/self/ns/net")
    assert proof["parent"] != proof["child"] and proof["interfaces"] == ["lo"]
    refute proof["default_route"]
    refute proof["ipv6_default_route"]

    for upload <- uploads(ctx) do
      assert upload["tls_version"] in ["TLSv1.2", "TLSv1.3"]
      assert upload["path"] == "/api/4510195390611458/envelope/"
      assert upload["host_verified"] and upload["sentry_auth_verified"]
      assert upload["account_headers_absent"]
      assert upload["decoded_size"] <= 524_288
    end

    assert [started] = events(ctx, "native_started")
    assert started["binary_sha256"] == @sha
    assert started["child_ca_only"] and started["proxy_never_forwards"]
    assert :ok = Session.close(pid)
    assert events(ctx, "native_closed") != []
    assert events(ctx, "peer_closed") != []
    assert events(ctx, "fixture_error") == []
    assert events(ctx, "forbidden_proxy") == []
  end

  defp digest(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  defp journal(ctx), do: ctx.root |> Path.join("journal.json") |> File.read!() |> JSON.decode!()
  defp events(ctx, name), do: Enum.filter(journal(ctx)["events"], &(&1["event"] == name))
  defp uploads(ctx), do: events(ctx, "upload")

  defp wait(predicate, remaining \\ 500)
  defp wait(_predicate, 0), do: flunk("Owned feedback observation/shutdown deadline")

  defp wait(predicate, remaining) do
    if value = predicate.() do
      value
    else
      Process.sleep(10)
      wait(predicate, remaining - 1)
    end
  end
end
