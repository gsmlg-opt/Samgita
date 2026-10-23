defmodule SamgitaCodexDriver.NativeRateReadProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  @moduletag :real_codex
  @moduletag :isolated_rate_read
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_rate_read_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @method "account/rateLimits/read"
  @account "isolated-auth-account"
  @plans ~w(free go plus pro prolite promax team self_serve_business_prolite self_serve_business_usage_based business ent26 enterprise_cbp_automation enterprise_cbp_usage_based enterprise edu edu_plus edu_pro unknown)
  @reached ~w(rate_limit_reached workspace_owner_credits_depleted workspace_member_credits_depleted workspace_owner_usage_limit_reached workspace_member_usage_limit_reached)

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-rate-read-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    for directory <- ~w(home codex workspace tmp), do: File.mkdir!(Path.join(root, directory))

    ctx = %{
      binary: Path.expand(binary),
      root: root,
      route: tags[:route] || "codex",
      parent_netns: File.read_link!("/proc/self/ns/net"),
      parent_userns: File.read_link!("/proc/self/ns/user")
    }

    on_exit(fn ->
      if File.exists?(Path.join(root, "journal.json")) do
        for started <- events(ctx, "native_started"),
            key <- ~w(pid controller_pid namespace_owner_pid),
            do: await(fn -> not File.exists?("/proc/#{started[key]}") end)

        assert length(events(ctx, "native_closed")) == length(events(ctx, "native_started"))
      end

      File.rm_rf!(root)
    end)

    ctx
  end

  for route <- ~w(codex chatgpt) do
    @tag route: route
    test "#{route} GET projects full and named quotas with reserve isolated to usage", ctx do
      pid = start(ctx)

      primary = backend_window(21, 61, 2_000_000_000)
      secondary = backend_window(99, 86_401, -1)

      individual = %{
        "source" => "synthetic_member_policy",
        "limit" => "25000.00",
        "used" => "8000.25",
        "remaining" => "16999.75",
        "used_percent" => 32,
        "remaining_percent" => 68,
        "reset_after_seconds" => 1,
        "reset_at" => -1
      }

      current =
        body()
        |> Map.merge(%{
          "rate_limit" => quota(primary, secondary),
          "credits" => %{"has_credits" => true, "unlimited" => false, "balance" => "123.4500"},
          "spend_control" => %{"reached" => true, "individual_limit" => individual},
          "rate_limit_reached_type" => %{"type" => "workspace_member_usage_limit_reached"},
          "rate_limit_reset_credits" => %{"available_count" => 7},
          "additional_rate_limits" => [
            %{
              "metered_feature" => "配额/λ🙂",
              "limit_name" => "Synthetic quota λ",
              "normal_model_slug" => "normal-model",
              "rate_limit" => quota(secondary, nil)
            },
            %{
              "metered_feature" => "empty-quota",
              "limit_name" => "Unavailable quota",
              "normal_model_slug" => nil
            }
          ]
        })

      configure(ctx, "rates", %{"body" => current})
      configure(ctx, "credits", %{"body" => %{"available_count" => 0, "credits" => []}})
      result = rates(pid, %{"supportsLunaReserve" => true, "excludeResetCreditDetails" => false})

      expected =
        snapshot(%{
          "primary" => window(21, 2, 2_000_000_000),
          "secondary" => window(99, 1_441, -1),
          "credits" => %{"hasCredits" => true, "unlimited" => false, "balance" => "123.4500"},
          "individualLimit" => %{
            "limit" => "25000.00",
            "used" => "8000.25",
            "remainingPercent" => 68,
            "resetsAt" => -1
          },
          "spendControlReached" => true,
          "rateLimitReachedType" => "workspace_member_usage_limit_reached"
        })

      assert result == %{
               "ordinaryUsageAllowed" => false,
               "accountId" => @account,
               "rateLimitUpsell" => current["rate_limit_upsell"],
               "rateLimits" => expected,
               "rateLimitsByLimitId" => %{
                 "codex" => expected,
                 "配额/λ🙂" =>
                   snapshot(%{
                     "limitId" => "配额/λ🙂",
                     "limitName" => "Synthetic quota λ",
                     "normalModelSlug" => "normal-model",
                     "primary" => window(99, 1_441, -1)
                   }),
                 "empty-quota" =>
                   snapshot(%{"limitId" => "empty-quota", "limitName" => "Unavailable quota"})
               },
               "rateLimitResetCredits" => %{"availableCount" => 0, "credits" => []}
             }

      assert length(reads(ctx, "rates")) == 1
      assert length(reads(ctx, "credits")) == 1
      assert hd(reads(ctx, "rates"))["luna_reserve"]
      refute hd(reads(ctx, "credits"))["luna_reserve"]
      prefix = if ctx.route == "codex", do: "/api/codex", else: "/backend-api/wham"
      assert hd(reads(ctx, "rates"))["path"] == prefix <> "/usage"
      assert hd(reads(ctx, "credits"))["path"] == prefix <> "/rate-limit-reset-credits"

      configure(ctx, "rates", %{
        "body" => Map.put(current, "spend_control", %{"reached" => false})
      })

      next = rates(pid, %{"supportsLunaReserve" => false, "excludeResetCreditDetails" => true})
      assert next["rateLimits"]["spendControlReached"] == false
      assert next["rateLimits"]["individualLimit"] == nil
      assert next["rateLimitResetCredits"] == %{"availableCount" => 7, "credits" => nil}
      refute List.last(reads(ctx, "rates"))["luna_reserve"]
      assert length(reads(ctx, "credits")) == 1
      finish(ctx, pid)
    end
  end

  test "backend plan SKUs and education aliases project independently from synthetic JWT plan",
       ctx do
    pid = start(ctx)

    cases =
      Enum.map(@plans, &{&1, &1}) ++
        [{"education", "edu"}] ++
        Enum.map(~w(guest free_workspace quorum k12 future_plan), &{&1, "unknown"})

    for {backend, expected} <- cases do
      configure(ctx, "rates", %{"body" => Map.put(body(), "plan_type", backend)})
      result = rates(pid, %{"excludeResetCreditDetails" => true})
      assert result["rateLimits"] == snapshot(%{"planType" => expected})
      assert result["rateLimitsByLimitId"] == %{"codex" => result["rateLimits"]}
    end

    assert length(reads(ctx, "rates")) == length(cases)
    assert reads(ctx, "credits") == []
    finish(ctx, pid)
  end

  test "all reached types preserve backend evidence while unknown and absent types stay null",
       ctx do
    pid = start(ctx)

    for value <- @reached ++ ["future_reason", nil] do
      details = if value, do: %{"type" => value}, else: nil
      configure(ctx, "rates", %{"body" => Map.put(body(), "rate_limit_reached_type", details)})
      result = rates(pid, %{"excludeResetCreditDetails" => true})
      expected = if value in @reached, do: value, else: nil
      assert result["rateLimits"]["rateLimitReachedType"] == expected
      assert result["rateLimitsByLimitId"]["codex"] == result["rateLimits"]
      assert result["ordinaryUsageAllowed"] == nil
    end

    assert length(reads(ctx, "rates")) == length(@reached) + 2
    finish(ctx, pid)
  end

  test "window duration edges and balance booleans preserve unavailable and explicit zero values",
       ctx do
    pid = start(ctx)

    for {seconds, percent, reset, minutes} <- [
          {0, 0, 0, nil},
          {-1, -1, -1, nil},
          {1, 1, -2, 1},
          {60, 100, 2_147_483_647, 1},
          {61, 101, -2_147_483_648, 2}
        ] do
      configure(ctx, "rates", %{
        "body" =>
          Map.put(body(), "rate_limit", quota(backend_window(percent, seconds, reset), nil))
      })

      result = rates(pid, %{"excludeResetCreditDetails" => true})
      assert result["rateLimits"]["primary"] == window(percent, minutes, reset)
      assert result["rateLimits"]["secondary"] == nil
      assert result["ordinaryUsageAllowed"] == false
    end

    for {credits, expected} <- [
          {%{"has_credits" => true, "unlimited" => true, "balance" => nil},
           %{"hasCredits" => true, "unlimited" => true, "balance" => nil}},
          {%{"has_credits" => false, "unlimited" => false, "balance" => "0.0000"},
           %{"hasCredits" => false, "unlimited" => false, "balance" => "0.0000"}},
          {%{"has_credits" => false, "unlimited" => true},
           %{"hasCredits" => false, "unlimited" => true, "balance" => nil}},
          {nil, nil}
        ] do
      configure(ctx, "rates", %{"body" => Map.put(body(), "credits", credits)})
      result = rates(pid, %{"excludeResetCreditDetails" => true})
      assert result["rateLimits"]["credits"] == expected
      assert result["rateLimits"]["spendControlReached"] == nil
    end

    assert length(reads(ctx, "rates")) == 9
    assert reads(ctx, "credits") == []
    finish(ctx, pid)
  end

  test "duplicate limit IDs retain native first singular snapshot and last map entry", ctx do
    pid = start(ctx)

    current =
      Map.merge(body(), %{
        "rate_limit" => quota(backend_window(10, 60, 1), nil),
        "additional_rate_limits" => [
          %{
            "metered_feature" => "codex",
            "limit_name" => "Duplicate quota",
            "normal_model_slug" => "duplicate-normal",
            "rate_limit" => quota(nil, backend_window(90, 120, 2))
          }
        ]
      })

    configure(ctx, "rates", %{"body" => current})
    result = rates(pid, %{"excludeResetCreditDetails" => true})
    assert result["rateLimits"] == snapshot(%{"primary" => window(10, 1, 1)})

    assert result["rateLimitsByLimitId"] == %{
             "codex" =>
               snapshot(%{
                 "limitName" => "Duplicate quota",
                 "normalModelSlug" => "duplicate-normal",
                 "secondary" => window(90, 2, 2)
               })
           }

    finish(ctx, pid)
  end

  test "reset detail statuses opaque IDs text offsets and capped rows preserve backend count",
       ctx do
    pid = start(ctx)

    rows = [
      credit(%{
        "id" => "积分/λ🙂",
        "status" => "redeeming",
        "granted_at" => "1970-01-01T00:59:59+01:00",
        "expires_at" => "1970-01-01T00:00:01Z",
        "title" => "Synthetic title λ",
        "description" => "Untrusted display text 🙂"
      }),
      credit(%{"id" => "already-used", "status" => "redeemed"}),
      credit(%{"id" => "available", "status" => "available", "title" => "Available"}),
      credit(%{"id" => "future", "status" => "future_status", "reset_type" => "future_reset"})
    ]

    configure(ctx, "rates", %{
      "body" => Map.put(body(), "rate_limit_reset_credits", %{"available_count" => 99})
    })

    configure(ctx, "credits", %{"body" => %{"available_count" => 9, "credits" => rows}})
    result = rates(pid, nil)

    assert result["rateLimitResetCredits"] == %{
             "availableCount" => 9,
             "credits" => [
               public_credit(%{
                 "id" => "积分/λ🙂",
                 "status" => "redeeming",
                 "grantedAt" => -1,
                 "expiresAt" => 1,
                 "title" => "Synthetic title λ",
                 "description" => "Untrusted display text 🙂"
               }),
               public_credit(%{"id" => "already-used", "status" => "redeemed"}),
               public_credit(%{
                 "id" => "available",
                 "status" => "available",
                 "title" => "Available"
               }),
               public_credit(%{"id" => "future", "status" => "unknown", "resetType" => "unknown"})
             ]
           }

    assert result["rateLimitResetCredits"]["availableCount"] > length(rows)
    refute hd(reads(ctx, "rates"))["luna_reserve"]
    finish(ctx, pid)
  end

  test "fetched empty details summary-only null and unavailable summary remain distinct", ctx do
    pid = start(ctx)

    for {summary, detail_count, expected} <- [
          {nil, 3, %{"availableCount" => 3, "credits" => []}},
          {%{"available_count" => 99}, 0, %{"availableCount" => 0, "credits" => []}}
        ] do
      configure(ctx, "rates", %{"body" => Map.put(body(), "rate_limit_reset_credits", summary)})

      configure(ctx, "credits", %{"body" => %{"available_count" => detail_count, "credits" => []}})

      assert rates(pid, %{})["rateLimitResetCredits"] == expected
    end

    configure(ctx, "credits", %{"status" => 404})
    configure(ctx, "rates", %{"body" => body()})
    assert rates(pid, %{"excludeResetCreditDetails" => false})["rateLimitResetCredits"] == nil

    configure(ctx, "rates", %{
      "body" => Map.put(body(), "rate_limit_reset_credits", %{"available_count" => 7})
    })

    assert rates(pid, %{})["rateLimitResetCredits"] == %{"availableCount" => 7, "credits" => nil}
    assert length(reads(ctx, "rates")) == 4
    assert length(reads(ctx, "credits")) == 4
    finish(ctx, pid)
  end

  test "one invalid expiry discards all detail rows and falls back to the usage summary", ctx do
    pid = start(ctx)

    configure(ctx, "rates", %{
      "body" => Map.put(body(), "rate_limit_reset_credits", %{"available_count" => 11})
    })

    configure(ctx, "credits", %{
      "body" => %{
        "available_count" => 2,
        "credits" => [
          credit(%{}),
          credit(%{"id" => "bad-expiry", "expires_at" => "invalid-date"})
        ]
      }
    })

    assert rates(pid, %{})["rateLimitResetCredits"] == %{"availableCount" => 11, "credits" => nil}
    assert length(reads(ctx, "credits")) == 1
    finish(ctx, pid)
  end

  test "official five-second detail timeout returns current usage summary without redemption",
       ctx do
    pid = start(ctx)

    configure(ctx, "rates", %{
      "body" => Map.put(body(), "rate_limit_reset_credits", %{"available_count" => 13})
    })

    configure(ctx, "credits", %{"hold" => true})
    started = System.monotonic_time(:millisecond)
    result = rates(pid, %{})
    elapsed = System.monotonic_time(:millisecond) - started
    assert result["rateLimitResetCredits"] == %{"availableCount" => 13, "credits" => nil}
    assert elapsed >= 4_000 and elapsed < 15_000
    assert length(events(ctx, "detail_waiting")) == 1
    assert Enum.filter(events(ctx, "read_finished"), &(&1["resource"] == "credits")) == []
    File.write!(Path.join(ctx.root, "release-credit-details"), "owned release")
    await(fn -> Enum.any?(events(ctx, "read_finished"), &(&1["resource"] == "credits")) end)
    assert length(reads(ctx, "rates")) == 1 and length(reads(ctx, "credits")) == 1
    finish(ctx, pid)
  end

  defp start(ctx) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: System.find_executable("python3"),
             args: [@script, "--codex", ctx.binary, "--root", ctx.root, "--route", ctx.route],
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
             Session.initialize(pid, %{"name" => "samgita_rate_read", "version" => "1"}, %{
               "experimentalApi" => false
             })

    await(fn -> Enum.any?(events(ctx, "native_input"), &(&1["method"] == "initialized")) end)
    pid
  end

  defp body do
    %{
      "plan_type" => "pro",
      "account_id" => @account,
      "user_id" => "isolated-auth-user",
      "rate_limit_upsell" => %{
        "banner_type" => "synthetic_read_only",
        "title" => "Untrusted display data"
      }
    }
  end

  defp backend_window(percent, seconds, reset),
    do: %{
      "used_percent" => percent,
      "limit_window_seconds" => seconds,
      "reset_after_seconds" => 1,
      "reset_at" => reset
    }

  defp quota(primary, secondary),
    do: %{
      "allowed" => false,
      "limit_reached" => true,
      "primary_window" => primary,
      "secondary_window" => secondary
    }

  defp window(percent, minutes, reset),
    do: %{"usedPercent" => percent, "windowDurationMins" => minutes, "resetsAt" => reset}

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

  defp credit(changes),
    do:
      Map.merge(
        %{
          "id" => "synthetic-credit",
          "reset_type" => "codex_rate_limits",
          "status" => "available",
          "granted_at" => "2026-06-14T00:00:00Z",
          "expires_at" => nil,
          "title" => nil,
          "description" => nil
        },
        changes
      )

  defp public_credit(changes),
    do:
      Map.merge(
        %{
          "id" => "synthetic-credit",
          "resetType" => "codexRateLimits",
          "status" => "available",
          "grantedAt" => 1_781_395_200,
          "expiresAt" => nil,
          "title" => nil,
          "description" => nil
        },
        changes
      )

  defp rates(pid, params) do
    id = "owned-rate-read-#{System.unique_integer([:positive])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, @method, params, id: id)

    result
  end

  defp configure(ctx, resource, changes) do
    path = Path.join(ctx.root, "rate-read-state.json")
    state = path |> File.read!() |> JSON.decode!()

    File.write!(
      path <> ".pending",
      JSON.encode!(Map.update!(state, resource, &Map.merge(&1, changes)))
    )

    File.rename!(path <> ".pending", path)
  end

  defp finish(ctx, pid) do
    id = "owned-loaded-#{System.unique_integer([:positive])}"

    assert {:ok, %{"id" => ^id, "result" => %{"data" => [], "nextCursor" => nil}}} =
             Session.request(pid, "thread/loaded/list", %{}, id: id)

    assert Session.status(pid).phase == :ready and Session.status(pid).interactions == 0
    assert Session.uncertain_operations(pid) == []
    assert {:ok, received} = Session.drain(pid, 10_000)

    refute Enum.any?(
             received,
             &(&1.kind == :server_request or &1.wire["method"] == "turn/started")
           )

    assert :ok = Session.close(pid)
    assert_isolation(ctx)
    assert_backend_closed(ctx)
  end

  defp assert_isolation(ctx) do
    proof = journal(ctx)["namespace"]
    assert proof["parent"] == ctx.parent_netns and proof["child"] != ctx.parent_netns
    assert proof["parent_user"] == ctx.parent_userns and proof["child_user"] != ctx.parent_userns
    assert proof["interfaces"] == ["lo"]
    refute proof["default_route"] or proof["ipv6_default_route"]
  end

  defp assert_backend_closed(ctx) do
    for read <- reads(ctx, nil) do
      assert read["bearer_verified"] and read["account_verified"] and read["host_verified"]
      assert read["bodyless_verified"]
    end

    for name <- ~w(fixture_error unexpected_http forbidden_headers),
        do: assert(events(ctx, name) == [])

    redactions = journal(ctx)["redaction_checked"]
    assert length(redactions) >= 3 and Enum.all?(redactions)
    assert length(events(ctx, "backend_closed")) == 1

    assert [%{"native_reaped" => true, "readers_stopped" => true, "output_valid" => true}] =
             events(ctx, "native_closed")

    for started <- events(ctx, "native_started"),
        key <- ~w(pid controller_pid namespace_owner_pid),
        do: await(fn -> not File.exists?("/proc/#{started[key]}") end)
  end

  defp journal(ctx), do: ctx.root |> Path.join("journal.json") |> File.read!() |> JSON.decode!()
  defp events(ctx, name), do: Enum.filter(journal(ctx)["events"], &(&1["event"] == name))
  defp reads(ctx, nil), do: events(ctx, "read")
  defp reads(ctx, resource), do: Enum.filter(reads(ctx, nil), &(&1["resource"] == resource))
  defp await(predicate, remaining \\ 1_000)
  defp await(_predicate, 0), do: flunk("Owned rate-read fixture observation deadline")

  defp await(predicate, remaining) do
    if value = predicate.() do
      value
    else
      Process.sleep(10)
      await(predicate, remaining - 1)
    end
  end
end
