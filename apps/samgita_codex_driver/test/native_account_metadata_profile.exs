defmodule SamgitaCodexDriver.NativeAccountMetadataProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag :isolated_account_metadata
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_account_metadata_fixture.py", __DIR__)
  @thread_id "019fc8ab-1fb2-7000-8000-000000000123"
  @plan_binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert System.find_executable("unshare"), "BLOCKED_ENV: unshare required"
    assert System.find_executable("ip"), "BLOCKED_ENV: ip required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-isolated-account-metadata-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      binary: binary,
      root: root,
      scenario: tags[:scenario] || "chatgpt",
      journal: Path.join(root, "isolated-account-metadata-journal.json")
    }
  end

  test "native rate-limit reads project multiple quotas and detailed reset credits", ctx do
    pid = start(ctx)
    result = rates(pid, nil)
    assert result["ordinaryUsageAllowed"] == true
    assert result["accountId"] == "isolated-auth-account"
    assert result["rateLimitUpsell"] == resource(ctx, "rates")["body"]["rate_limit_upsell"]
    primary = snapshot(%{"primary" => window(42, 60)})

    other =
      snapshot(%{
        "limitId" => "codex_other",
        "limitName" => "Other quota",
        "normalModelSlug" => "normal-model",
        "primary" => window(88, 2)
      })

    assert result["rateLimits"] == primary
    assert result["rateLimitsByLimitId"] == %{"codex" => primary, "codex_other" => other}

    assert result["rateLimitResetCredits"] == %{
             "availableCount" => 2,
             "credits" => [
               %{
                 "id" => "credit-known",
                 "resetType" => "codexRateLimits",
                 "status" => "available",
                 "grantedAt" => 1_781_395_200,
                 "expiresAt" => 1_781_481_600,
                 "title" => "Synthetic grant",
                 "description" => nil
               },
               %{
                 "id" => "credit-future",
                 "resetType" => "unknown",
                 "status" => "unknown",
                 "grantedAt" => 1_781_395_200,
                 "expiresAt" => nil,
                 "title" => nil,
                 "description" => nil
               }
             ]
           }

    assert length(reads(ctx, "rates")) == 1
    assert length(reads(ctx, "credits")) == 1
    refute hd(reads(ctx, "rates"))["luna_reserve"]
    finish(ctx, pid)
  end

  test "rate-limit detail failures retain summary while opt-out and reserve support stay explicit",
       ctx do
    pid = start(ctx)
    state(ctx, "credits", %{"status" => 500})
    assert rates(pid)["rateLimitResetCredits"] == %{"availableCount" => 3, "credits" => nil}

    state(ctx, "rates", %{
      "body" =>
        Map.put(resource(ctx, "rates")["body"], "rate_limit_reset_credits", %{
          "available_count" => 7
        })
    })

    result = rates(pid, %{"excludeResetCreditDetails" => true, "supportsLunaReserve" => true})
    assert result["rateLimitResetCredits"] == %{"availableCount" => 7, "credits" => nil}
    assert length(reads(ctx, "credits")) == 1
    assert List.last(reads(ctx, "rates"))["luna_reserve"]

    bad_credit =
      resource(ctx, "credits")["body"]
      |> put_in(["credits", Access.at(0), "granted_at"], "invalid-date")

    state(ctx, "credits", %{"status" => 200, "body" => bad_credit})
    assert rates(pid)["rateLimitResetCredits"] == %{"availableCount" => 7, "credits" => nil}
    assert length(reads(ctx, "rates")) == 3
    assert length(reads(ctx, "credits")) == 2
    finish(ctx, pid)
  end

  test "rate-limit account-bound banners require matching identity and nullable quotas stay unavailable",
       ctx do
    pid = start(ctx)
    base = resource(ctx, "rates")["body"]

    for changes <- [
          %{"account_id" => "other-account"},
          %{"user_id" => "other-user"},
          %{"account_id" => nil},
          %{"user_id" => nil}
        ] do
      state(ctx, "rates", %{"body" => Map.merge(base, changes)})
      result = rates(pid, %{"excludeResetCreditDetails" => true})
      assert result["ordinaryUsageAllowed"] == nil
      assert result["rateLimitUpsell"] == nil
      assert result["rateLimits"]["primary"] == window(42, 60)
    end

    state(ctx, "rates", %{"body" => %{"plan_type" => "guest", "rate_limit" => nil}})
    result = rates(pid, %{"excludeResetCreditDetails" => true})
    assert result["rateLimits"] == snapshot(%{"planType" => "unknown"})
    assert result["rateLimitsByLimitId"] == %{"codex" => result["rateLimits"]}
    assert result["rateLimitResetCredits"] == nil
    assert result["accountId"] == nil
    assert result["ordinaryUsageAllowed"] == nil
    assert result["rateLimitUpsell"] == nil
    assert length(reads(ctx, "rates")) == 5
    assert reads(ctx, "credits") == []
    finish(ctx, pid)
  end

  test "rate-limit HTTP and malformed backend failures remain explicit native errors", ctx do
    pid = start(ctx)

    for status <- [429, 500, 403, 401] do
      state(ctx, "rates", %{"status" => status})

      error =
        upstream_error(pid, "account/rateLimits/read", %{"excludeResetCreditDetails" => true})

      assert error["code"] == -32_603
      assert error["message"] =~ "failed to fetch codex rate limits"
      assert List.last(reads(ctx, "rates"))["status"] == status
    end

    state(ctx, "rates", %{"status" => 200, "body" => %{"plan_type" => 9}})

    assert upstream_error(pid, "account/rateLimits/read", %{"excludeResetCreditDetails" => true})[
             "code"
           ] == -32_603

    assert length(reads(ctx, "rates")) == 5
    assert reads(ctx, "credits") == []
    finish(ctx, pid)
  end

  test "account usage reads current profile stats and distinguishes null data from errors", ctx do
    pid = start(ctx)

    assert usage(pid, nil) == %{
             "summary" => %{
               "lifetimeTokens" => 123,
               "peakDailyTokens" => 45,
               "longestRunningTurnSec" => 67,
               "currentStreakDays" => 8,
               "longestStreakDays" => 9
             },
             "dailyUsageBuckets" => [%{"startDate" => "2026-06-14", "tokens" => 10}],
             "threadUsage" => nil
           }

    state(ctx, "profile", %{"body" => %{"stats" => %{}}})
    assert usage(pid, %{"threadId" => nil}) == empty_usage()

    for status <- [429, 500, 403] do
      state(ctx, "profile", %{"status" => status})
      error = upstream_error(pid, "account/usage/read", %{})
      assert error["code"] == -32_603
      assert error["message"] =~ "failed to fetch token usage profile"
    end

    state(ctx, "profile", %{
      "status" => 200,
      "body" => %{"stats" => %{"lifetime_tokens" => "invalid"}}
    })

    assert upstream_error(pid, "account/usage/read", %{})["code"] == -32_603
    assert length(reads(ctx, "profile")) == 6
    assert reads(ctx, "thread") == []
    finish(ctx, pid)
  end

  test "thread usage canonicalizes IDs and separates route absence from failed reads", ctx do
    pid = start(ctx)
    result = usage(pid, %{"threadId" => String.upcase(@thread_id)})
    assert result["summary"] == empty_usage()["summary"]
    assert result["dailyUsageBuckets"] == nil

    assert result["threadUsage"] == %{
             "threadId" => @thread_id,
             "estimatedUsageCreditsMicros" => 46_000_000,
             "estimatedUsageUsdMicros" => nil,
             "groups" => [
               %{
                 "model" => "synthetic-model",
                 "reasoningEffort" => "high",
                 "speed" => "fast",
                 "estimatedUsageCreditsMicros" => 46_000_000,
                 "netNewInputTokens" => 80,
                 "cachedInputTokens" => 20,
                 "inputTokens" => 100,
                 "outputTokens" => 40,
                 "totalTokens" => 140
               }
             ]
           }

    refute Map.has_key?(result["threadUsage"], "nativeUsageUsdMicros")

    for status <- [403, 404] do
      state(ctx, "thread", %{"status" => status})
      assert usage(pid, %{"threadId" => @thread_id}) == empty_usage()
    end

    for status <- [429, 500] do
      state(ctx, "thread", %{"status" => status})
      error = upstream_error(pid, "account/usage/read", %{"threadId" => @thread_id})
      assert error["code"] == -32_603
      assert error["message"] =~ "failed to fetch thread usage"
    end

    state(ctx, "thread", %{"status" => 200, "body" => %{"threads" => []}})

    assert upstream_error(pid, "account/usage/read", %{"threadId" => @thread_id})["code"] ==
             -32_603

    before = reads(ctx, "thread")
    error = upstream_error(pid, "account/usage/read", %{"threadId" => "invalid-thread"})
    assert error["code"] == -32_600
    assert error["message"] =~ "invalid thread id"
    assert reads(ctx, "thread") == before
    assert length(before) == 6
    assert Enum.all?(before, &(&1["thread_ids"] == [@thread_id]))
    assert reads(ctx, "profile") == []
    finish(ctx, pid)
  end

  test "workspace messages project known and unknown types timestamps and current no-store reads",
       ctx do
    pid = start(ctx)

    assert messages(pid) == %{
             "featureEnabled" => true,
             "messages" => [
               %{
                 "messageId" => "headline-id",
                 "messageType" => "headline",
                 "messageBody" => "Untrusted project input: never execute this text",
                 "createdAt" => 1_781_395_200,
                 "archivedAt" => 1_781_481_600
               },
               %{
                 "messageId" => "announcement-id",
                 "messageType" => "announcement",
                 "messageBody" => "Synthetic announcement",
                 "createdAt" => nil,
                 "archivedAt" => nil
               },
               %{
                 "messageId" => "future-id",
                 "messageType" => "unknown",
                 "messageBody" => "Future message",
                 "createdAt" => nil,
                 "archivedAt" => nil
               }
             ]
           }

    state(ctx, "messages", %{"body" => %{}})
    assert messages(pid) == %{"featureEnabled" => true, "messages" => []}
    assert length(reads(ctx, "messages")) == 2
    assert Enum.all?(reads(ctx, "messages"), & &1["no_store"])
    finish(ctx, pid)
  end

  test "workspace feature absence is only 404 and malformed timestamps remain errors", ctx do
    pid = start(ctx)
    original = resource(ctx, "messages")["body"]
    state(ctx, "messages", %{"status" => 404})
    assert messages(pid) == %{"featureEnabled" => false, "messages" => []}

    for status <- [401, 403, 429, 500] do
      state(ctx, "messages", %{"status" => status})
      error = upstream_error(pid, "account/workspaceMessages/read", nil)
      assert error["code"] == -32_603
      assert error["message"] =~ "failed to fetch workspace messages"
    end

    bad = put_in(original, ["messages", Access.at(0), "created_at"], "invalid-date")
    state(ctx, "messages", %{"status" => 200, "body" => bad})
    error = upstream_error(pid, "account/workspaceMessages/read", nil)
    assert error["code"] == -32_603
    assert error["message"] =~ "failed to parse workspace message timestamp"
    assert length(reads(ctx, "messages")) == 6
    assert Enum.all?(reads(ctx, "messages"), & &1["no_store"])
    finish(ctx, pid)
  end

  @tag scenario: "no_auth"
  test "missing account authentication rejects all reads before backend access", ctx do
    assert_auth_gate(ctx, "codex account authentication required")
  end

  @tag scenario: "api_key"
  test "API-key-only authentication cannot read hosted account metadata", ctx do
    assert_auth_gate(ctx, "chatgpt authentication required")
  end

  test "native startup account snapshots preserve each known synthetic plan SKU", ctx do
    assert_plan_binary(ctx)

    for {claim, expected} <- [
          {"free", "free"},
          {"go", "go"},
          {"plus", "plus"},
          {"pro", "pro"},
          {"prolite", "prolite"},
          {"promax", "promax"},
          {"team", "team"},
          {"self_serve_business_prolite", "self_serve_business_prolite"},
          {"self_serve_business_usage_based", "self_serve_business_usage_based"},
          {"business", "business"},
          {"ent26", "ent26"},
          {"enterprise_cbp_automation", "enterprise_cbp_automation"},
          {"enterprise_cbp_usage_based", "enterprise_cbp_usage_based"},
          {"enterprise", "enterprise"},
          {"edu", "edu"},
          {"edu_plus", "edu_plus"},
          {"edu_pro", "edu_pro"}
        ] do
      assert_plan_snapshot(ctx, claim, expected)
    end
  end

  test "future and absent synthetic token plans emit unknown account metadata", ctx do
    assert_plan_binary(ctx)
    assert_plan_snapshot(ctx, "future_metadata_plan", "unknown")
    assert_plan_snapshot(ctx, "omit_plan_claim", "unknown")
  end

  defp assert_plan_binary(ctx) do
    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @plan_binary_sha
  end

  defp assert_plan_snapshot(ctx, claim, expected) do
    root = Path.join(ctx.root, "plan-#{claim}")
    File.mkdir!(root)

    owned = %{
      ctx
      | root: root,
        journal: Path.join(root, "isolated-account-metadata-journal.json")
    }

    pid = start(owned, claim)
    auth_path = Path.join(root, "codex/auth.json")
    config_path = Path.join(root, "codex/config.toml")
    auth_digest = :crypto.hash(:sha256, File.read!(auth_path))
    config_bytes = File.read!(config_path)
    assert_synthetic_plan(auth_path, claim)

    received = account_snapshot(pid, System.monotonic_time(:millisecond) + 10_000)
    expected_update = %{"authMode" => "chatgpt", "planType" => expected}
    assert_account_updates(received, expected_update)

    expected_account = %{
      "account" => %{
        "type" => "chatgpt",
        "email" => "isolated-auth@synthetic.invalid",
        "planType" => expected
      },
      "requiresOpenaiAuth" => true,
      "workspaceRouting" => %{
        "chatgptAccountId" => "isolated-auth-account",
        "backendOrigin" => "https://synthetic.invalid",
        "accountRoutingOverride" => "NO_CONSTRAINT"
      }
    }

    for _ <- 1..2 do
      assert call(pid, "account/read", %{"refreshToken" => false}) === expected_account
      assert :crypto.hash(:sha256, File.read!(auth_path)) === auth_digest
      assert File.read!(config_path) === config_bytes
      assert_synthetic_plan(auth_path, claim)
    end

    assert {:ok, later} = Session.drain(pid)
    assert_account_updates(received ++ later, expected_update)
    assert Session.status(pid).phase == :ready
    assert Session.status(pid).pending == 0
    assert Session.status(pid).interactions == 0
    assert Session.uncertain_operations(pid) === []
    assert resource(owned, "rates")["body"]["plan_type"] === "pro"
    assert Enum.filter(events(owned), &(&1["event"] == "read")) === []
    finish(owned, pid)

    assert :crypto.hash(:sha256, File.read!(auth_path)) === auth_digest
    assert File.read!(config_path) === config_bytes
    assert_synthetic_plan(auth_path, claim)

    inputs = for event <- events(owned), event["event"] == "native_input", do: event["method"]
    assert Enum.count(inputs, &(&1 == "account/read")) == 2

    assert Enum.all?(
             inputs,
             &(&1 in ["initialize", "initialized", "account/read", "thread/loaded/list"])
           )

    metadata_paths =
      for event <- events(owned), event["event"] == "startup_metadata", do: event["path"]

    assert "/backend-api/wham/accounts/check" in metadata_paths

    assert Enum.all?(
             metadata_paths,
             &(&1 in [
                 "/backend-api/wham/config/bundle",
                 "/backend-api/wham/accounts/check",
                 "/backend-api/wham/settings/user"
               ])
           )
  end

  defp assert_synthetic_plan(path, claim) do
    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
    auth = path |> File.read!() |> JSON.decode!()
    assert auth["auth_mode"] === "chatgpt"
    assert auth["OPENAI_API_KEY"] === nil
    assert auth["tokens"]["account_id"] === "isolated-auth-account"
    token = auth["tokens"]["id_token"]
    assert is_binary(token) and byte_size(token) <= 4096
    assert [header, payload, "c3ludGhldGlj"] = String.split(token, ".")

    assert header |> Base.url_decode64!(padding: false) |> JSON.decode!() === %{
             "alg" => "none",
             "typ" => "JWT"
           }

    claims = payload |> Base.url_decode64!(padding: false) |> JSON.decode!()
    assert Enum.sort(Map.keys(claims)) === ["email", "exp", "https://api.openai.com/auth"]
    assert claims["email"] === "isolated-auth@synthetic.invalid"
    assert is_integer(claims["exp"])
    now = System.system_time(:second)
    assert claims["exp"] > now and claims["exp"] <= now + 3600

    identity = %{
      "chatgpt_account_id" => "isolated-auth-account",
      "chatgpt_user_id" => "isolated-auth-user"
    }

    expected =
      if claim == "omit_plan_claim",
        do: identity,
        else: Map.put(identity, "chatgpt_plan_type", claim)

    assert Map.fetch!(claims, "https://api.openai.com/auth") === expected
  end

  defp account_snapshot(pid, deadline, received \\ []) do
    assert {:ok, current} = Session.drain(pid)
    received = received ++ current

    if Enum.any?(received, &(&1.wire["method"] == "account/updated")) do
      received
    else
      assert System.monotonic_time(:millisecond) < deadline, "native account snapshot deadline"
      assert Session.status(pid).phase == :ready

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("unexpected native account snapshot gap")
      after
        10 -> :ok
      end

      account_snapshot(pid, deadline, received)
    end
  end

  defp assert_account_updates(received, expected) do
    updates = Enum.filter(received, &(&1.wire["method"] == "account/updated"))
    assert updates != []

    for event <- updates do
      assert event.wire["method"] === "account/updated"
      assert Map.fetch!(event.wire, "params") === expected
    end

    refute Enum.any?(received, &(&1.kind == :server_request))
    refute Enum.any?(received, &(&1.wire["method"] == "turn/started"))
  end

  defp assert_auth_gate(ctx, prefix) do
    pid = start(ctx)

    for {method, noun} <- [
          {"account/rateLimits/read", "rate limits"},
          {"account/usage/read", "token usage"},
          {"account/workspaceMessages/read", "workspace messages"}
        ] do
      error = upstream_error(pid, method, nil)
      assert error == %{"code" => -32_600, "message" => "#{prefix} to read #{noun}"}
    end

    assert Enum.filter(events(ctx), &(&1["event"] == "read")) == []
    finish(ctx, pid)
  end

  defp start(ctx, plan_case \\ nil) do
    args = [@script, "--codex", ctx.binary, "--root", ctx.root, "--scenario", ctx.scenario]
    args = if plan_case, do: args ++ ["--plan-case", plan_case], else: args

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: System.find_executable("python3"),
             args: args,
             env: %{"CODEX_HOME" => Path.join(ctx.root, "codex")}
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_isolated_account_metadata", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp rates(pid, params \\ %{}), do: call(pid, "account/rateLimits/read", params)
  defp usage(pid, params), do: call(pid, "account/usage/read", params)
  defp messages(pid), do: call(pid, "account/workspaceMessages/read", nil)

  defp snapshot(changes) do
    Map.merge(
      %{
        "limitId" => "codex",
        "limitName" => nil,
        "normalModelSlug" => nil,
        "primary" => nil,
        "secondary" => nil,
        "credits" => nil,
        "individualLimit" => nil,
        "spendControlReached" => nil,
        "planType" => "pro",
        "rateLimitReachedType" => nil
      },
      changes
    )
  end

  defp window(percent, mins),
    do: %{"usedPercent" => percent, "windowDurationMins" => mins, "resetsAt" => 2_000_000_000}

  defp empty_usage do
    %{
      "summary" => %{
        "lifetimeTokens" => nil,
        "peakDailyTokens" => nil,
        "longestRunningTurnSec" => nil,
        "currentStreakDays" => nil,
        "longestStreakDays" => nil
      },
      "dailyUsageBuckets" => nil,
      "threadUsage" => nil
    }
  end

  defp resource(ctx, key),
    do:
      ctx.root
      |> Path.join("account-state.json")
      |> File.read!()
      |> JSON.decode!()
      |> Map.fetch!(key)

  defp state(ctx, key, changes) do
    path = Path.join(ctx.root, "account-state.json")
    current = path |> File.read!() |> JSON.decode!()
    pending = path <> ".pending"
    File.write!(pending, JSON.encode!(Map.update!(current, key, &Map.merge(&1, changes))))
    File.rename!(pending, path)
  end

  defp finish(ctx, pid) do
    data = journal(ctx)
    assert data["namespace"]["parent"] != data["namespace"]["child"]
    assert data["namespace"]["interfaces"] == ["lo"]
    refute data["namespace"]["default_route"]
    refute Enum.any?(events(ctx), &(&1["event"] in ["unexpected_http", "fixture_error"]))

    for event <- events(ctx), event["event"] == "read" do
      assert event["bearer_verified"]
      assert event["account_verified"]
    end

    assert call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert Session.status(pid).phase == :ready

    auth =
      case File.read(Path.join(ctx.root, "codex/auth.json")) do
        {:ok, encoded} -> JSON.decode!(encoded)
        {:error, :enoent} -> %{}
      end

    secrets = Map.values(auth["tokens"] || %{}) ++ [auth["OPENAI_API_KEY"]]

    for path <- [ctx.journal, Path.join(ctx.root, "native-stderr.log")],
        secret <- secrets,
        is_binary(secret) and secret != "" do
      refute File.read!(path) =~ secret
    end

    started = Enum.find(events(ctx), &(&1["event"] == "native_started"))
    assert :ok = Session.close(pid)

    for key <- ["pid", "controller_pid", "namespace_owner_pid"] do
      refute File.exists?("/proc/#{Map.fetch!(started, key)}"),
             "owned account metadata process must be reaped"
    end

    assert Enum.any?(events(ctx), &(&1["event"] == "native_closed"))
    refute Enum.any?(events(ctx), &(&1["event"] in ["unexpected_http", "fixture_error"]))
  end

  defp journal(ctx), do: ctx.journal |> File.read!() |> JSON.decode!()
  defp events(ctx), do: journal(ctx)["events"]

  defp reads(ctx, resource),
    do: Enum.filter(events(ctx), &(&1["event"] == "read" and &1["resource"] == resource))

  defp call(pid, method, params) do
    case Session.request(pid, method, params) do
      {:ok, %{"result" => result}} -> result
      {:error, %Error{wire: wire}} -> flunk("native #{method} failed: #{inspect(wire)}")
      other -> flunk("native #{method} unexpected result: #{inspect(other)}")
    end
  end

  defp upstream_error(pid, method, params) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             Session.request(pid, method, params)

    error
  end
end
