defmodule SamgitaCodexDriver.NativeAccountControlProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag :isolated_account_control
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_account_control_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @consume "account/rateLimitResetCredit/consume"
  @nudge "account/sendAddCreditsNudgeEmail"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-account-control-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for directory <- ~w(home codex workspace tmp), do: File.mkdir_p!(Path.join(root, directory))

    ctx = %{
      binary: Path.expand(binary),
      root: root,
      route: tags[:route] || "codex",
      auth: tags[:auth] || "chatgpt"
    }

    on_exit(fn ->
      if File.exists?(Path.join(root, "journal.json")) do
        started = List.first(events(ctx, "native_started"))

        if started do
          for key <- ~w(pid controller_pid namespace_owner_pid),
              do: wait(fn -> not File.exists?("/proc/#{started[key]}") end)

          assert events(ctx, "native_closed") != []
        end
      end

      File.rm_rf!(root)
    end)

    ctx
  end

  for route <- ~w(codex chatgpt) do
    @tag route: route
    test "#{route} consume preserves outcomes selected and absent credits and Unicode", ctx do
      pid = start(ctx)

      cases = [
        {"reset", "reset", %{"idempotencyKey" => "请求-λ🙂", "creditId" => "积分-λ🙂"}},
        {"nothing_to_reset", "nothingToReset", %{"idempotencyKey" => "omitted-credit"}},
        {"no_credit", "noCredit", %{"idempotencyKey" => "null-credit", "creditId" => nil}},
        {"already_redeemed", "alreadyRedeemed", %{"idempotencyKey" => "请求-λ🙂"}}
      ]

      expected =
        for {code, outcome, params} <- cases do
          body = %{"redeem_request_id" => params["idempotencyKey"]}

          body =
            if is_binary(params["creditId"]),
              do: Map.put(body, "credit_id", params["creditId"]),
              else: body

          configure(ctx, "consume", body, %{"code" => code, "windows_reset" => 2})
          assert call(pid, @consume, params) == %{"outcome" => outcome}
          body
        end

      assert Enum.map(posts(ctx, "consume"), & &1["body"]) == expected
      assert length(posts(ctx, "consume")) == 4
      assert posts(ctx, "nudge") == []
      finish(ctx, pid)
    end

    @tag route: route
    test "#{route} nudge maps both credit types bodyless success and cooldown", ctx do
      pid = start(ctx)

      cases = [
        {"credits", 200, "sent"},
        {"usage_limit", 200, "sent"},
        {"credits", 204, "sent"},
        {"usage_limit", 429, "cooldown_active"}
      ]

      for {credit, status, result} <- cases do
        configure(ctx, "nudge", %{"credit_type" => credit}, %{}, %{"status" => status})
        assert call(pid, @nudge, %{"creditType" => credit}) == %{"status" => result}
      end

      assert Enum.map(posts(ctx, "nudge"), &{&1["body"], &1["status"]}) ==
               Enum.map(cases, fn {credit, status, _} -> {%{"credit_type" => credit}, status} end)

      assert posts(ctx, "consume") == []
      finish(ctx, pid)
    end

    @tag route: route
    test "#{route} native backend errors retain failures without retrying POSTs", ctx do
      pid = start(ctx)
      params = %{"idempotencyKey" => "backend-failure"}
      expected = %{"redeem_request_id" => "backend-failure"}

      for changes <- [
            %{"status" => 500},
            %{"body" => %{"code" => "future_code"}},
            %{"body" => %{"windows_reset" => 1}},
            %{"raw_response" => "not-json"}
          ] do
        configure(ctx, "consume", expected, %{"code" => "reset"}, changes)
        failure = error(pid, @consume, params)
        assert failure["code"] == -32_603
        assert failure["message"] =~ "failed to consume rate limit reset:"
        refute Map.has_key?(failure, "data")
      end

      configure(ctx, "nudge", %{"credit_type" => "credits"}, %{"error" => "owned failure"}, %{
        "status" => 500
      })

      failure = error(pid, @nudge, %{"creditType" => "credits"})
      assert failure["code"] == -32_603
      assert failure["message"] =~ "failed to notify workspace owner:"
      refute Map.has_key?(failure, "data")
      assert length(posts(ctx, "consume")) == 4
      assert length(posts(ctx, "nudge")) == 1
      finish(ctx, pid)
    end
  end

  test "native empty-string validation rejects before any backend POST", ctx do
    pid = start(ctx)

    for {params, message} <- [
          {%{"idempotencyKey" => ""}, "idempotencyKey must not be empty"},
          {%{"idempotencyKey" => "valid", "creditId" => ""}, "creditId must not be empty"}
        ] do
      assert error(pid, @consume, params) == %{"code" => -32_600, "message" => message}
    end

    assert posts(ctx) == []
    finish(ctx, pid)
  end

  @tag auth: "no_auth"
  test "missing account authentication rejects both operations before HTTP", ctx do
    auth_gate(ctx, "codex account authentication required")
  end

  @tag auth: "api_key"
  test "API-key-only authentication rejects both hosted-account operations before HTTP", ctx do
    auth_gate(ctx, "chatgpt authentication required")
  end

  test "client schemas and actual native parsing reject malformed parameters independently",
       ctx do
    pid = start(ctx)

    for {method, params} <- [
          {@consume, %{}},
          {@consume, %{"idempotencyKey" => 42}},
          {@consume, %{"idempotencyKey" => "valid", "creditId" => false}},
          {@nudge, %{}},
          {@nudge, %{"creditType" => "usageLimit"}},
          {@nudge, %{"creditType" => nil}}
        ] do
      before = length(events(ctx, "native_input"))

      assert {:error, %Error{code: :schema_violation, uncertain: false}} =
               Session.request(pid, method, params)

      assert length(events(ctx, "native_input")) == before
      failure = error(pid, method, params, validation: :wire)
      assert failure["code"] == -32_600
      assert failure["message"] =~ "Invalid request:"
      assert length(events(ctx, "native_input")) == before + 1
    end

    assert posts(ctx) == []
    finish(ctx, pid)
  end

  test "a held consume POST remains uncertain after local timeout and is never replayed", ctx do
    pid = start(ctx)

    configure(
      ctx,
      "consume",
      %{"redeem_request_id" => "owned-ambiguous"},
      %{
        "code" => "reset"
      },
      %{"hold" => true}
    )

    task =
      Task.async(fn ->
        Session.request(pid, @consume, %{"idempotencyKey" => "owned-ambiguous"},
          id: "owned-ambiguous",
          timeout_ms: 1_000
        )
      end)

    wait(fn -> length(posts(ctx, "consume")) == 1 end)
    assert {:error, %Error{code: :deadline_exceeded, uncertain: true}} = Task.await(task)
    assert [%{id: "owned-ambiguous", method: @consume}] = Session.uncertain_operations(pid)
    File.write!(Path.join(ctx.root, "release-response"), "release owned response")
    received = collect_late(pid)

    assert Enum.any?(received, fn event ->
             event.kind == :late_response and event.wire["id"] == "owned-ambiguous" and
               event.wire["result"] == %{"outcome" => "reset"}
           end)

    assert [%{id: "owned-ambiguous"}] = Session.uncertain_operations(pid)
    assert length(posts(ctx, "consume")) == 1
    assert posts(ctx, "nudge") == []
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
               "--codex",
               ctx.binary,
               "--root",
               ctx.root,
               "--route",
               ctx.route,
               "--auth",
               ctx.auth
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
             Session.initialize(pid, %{"name" => "samgita_account_control", "version" => "1"})

    wait(fn -> Enum.any?(events(ctx, "native_input"), &(&1["method"] == "initialized")) end)
    pid
  end

  defp auth_gate(ctx, prefix) do
    pid = start(ctx)

    for {method, params, suffix} <- [
          {@consume, %{"idempotencyKey" => "auth-gate"}, "for rate limit reset credits"},
          {@nudge, %{"creditType" => "credits"}, "to notify workspace owner"}
        ] do
      assert error(pid, method, params) == %{
               "code" => -32_600,
               "message" => "#{prefix} #{suffix}"
             }
    end

    assert posts(ctx) == []
    finish(ctx, pid)
  end

  defp configure(ctx, resource, expected, body, changes \\ %{}) do
    path = Path.join(ctx.root, "responses.json")
    current = path |> File.read!() |> JSON.decode!()
    value = Map.merge(%{"expected" => expected, "body" => body, "status" => 200}, changes)
    File.write!(path <> ".pending", JSON.encode!(Map.put(current, resource, value)))
    File.rename!(path <> ".pending", path)
  end

  defp finish(ctx, pid) do
    assert call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert Session.status(pid).phase == :ready
    assert Session.status(pid).interactions == 0
    assert {:ok, received} = Session.drain(pid)

    assert Enum.all?(
             received,
             &(&1.kind != :server_request and &1.wire["method"] != "turn/started")
           )

    data = journal(ctx)
    proof = data["namespace"]
    assert proof["parent"] == File.read_link!("/proc/self/ns/net")
    assert proof["parent"] != proof["child"] and proof["interfaces"] == ["lo"]
    refute proof["default_route"]
    refute proof["ipv6_default_route"]

    assert_posts(ctx)
    assert :ok = Session.close(pid)
    assert events(ctx, "native_closed") != []

    for name <- ~w(unexpected_http forbidden_body fixture_error forbidden_native),
        do: assert(events(ctx, name) == [])

    for event <- events(ctx, "native_input"),
        do:
          assert(
            event["method"] in [
              "initialize",
              "initialized",
              @consume,
              @nudge,
              "thread/loaded/list"
            ]
          )

    for secret <- journal(ctx)["redaction_checked"], do: assert(secret == true)
  end

  defp assert_posts(ctx) do
    for event <- posts(ctx) do
      assert event["bearer_verified"] and event["account_verified"]
      assert event["content_type_verified"] and event["host_verified"] and event["body_verified"]
      assert event["route"] == ctx.route
      assert event["path"] == path(ctx.route, event["resource"])
    end
  end

  defp path(route, resource) do
    prefix = if route == "codex", do: "/api/codex", else: "/backend-api/wham"

    suffix =
      if resource == "consume",
        do: "/rate-limit-reset-credits/consume",
        else: "/accounts/send_add_credits_nudge_email"

    prefix <> suffix
  end

  defp collect_late(pid, received \\ [], remaining \\ 500)
  defp collect_late(_pid, _received, 0), do: flunk("Owned account-control late-response deadline")

  defp collect_late(pid, received, remaining) do
    assert {:ok, current} = Session.drain(pid)
    received = received ++ current

    if Enum.any?(received, &(&1.kind == :late_response)) do
      received
    else
      Process.sleep(10)
      collect_late(pid, received, remaining - 1)
    end
  end

  defp call(pid, method, params) do
    id = "owned-call-#{System.unique_integer([:positive])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, method, params, id: id)

    result
  end

  defp error(pid, method, params, opts \\ []) do
    id = "owned-error-#{System.unique_integer([:positive])}"

    assert {:error, %Error{code: :upstream_error, wire: %{"id" => ^id, "error" => failure}}} =
             Session.request(pid, method, params, Keyword.put(opts, :id, id))

    failure
  end

  defp journal(ctx), do: ctx.root |> Path.join("journal.json") |> File.read!() |> JSON.decode!()
  defp events(ctx, name), do: Enum.filter(journal(ctx)["events"], &(&1["event"] == name))
  defp posts(ctx), do: events(ctx, "post")
  defp posts(ctx, resource), do: Enum.filter(posts(ctx), &(&1["resource"] == resource))

  defp wait(predicate, remaining \\ 500)
  defp wait(_predicate, 0), do: flunk("Owned account-control observation deadline")

  defp wait(predicate, remaining) do
    if value = predicate.() do
      value
    else
      Process.sleep(10)
      wait(predicate, remaining - 1)
    end
  end
end
