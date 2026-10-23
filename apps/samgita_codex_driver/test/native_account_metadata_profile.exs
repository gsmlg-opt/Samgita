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
               "--scenario",
               ctx.scenario
             ],
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
