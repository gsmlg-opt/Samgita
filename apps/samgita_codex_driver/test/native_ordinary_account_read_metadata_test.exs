defmodule SamgitaCodexDriver.NativeOrdinaryAccountReadMetadataTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_account_read_metadata_fixture.py", __DIR__)
  @script_sha "e69015fb0979cddb5c4752934ae951b55a079929bc7a40a11cbf724bc218cb12"
  @base Path.expand("../../../scripts/codex/ordinary_app_context_fixture.py", __DIR__)
  @base_sha "2f25436a2b5694390d64305b9566ce3859eea5cb81f8b212c125eb05db4126e1"
  @cleanup Path.join(__DIR__, "support/stdio_session_fixture.ex")
  @cleanup_sha "a164a57adff4cba26360a7e2788b8c3e9e6829a0a5e77eae28e857c29dc201a0"
  @schemas %{
    "ClientRequest.json" => "92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352",
    "v2/NullableGetAccountRateLimitsParams.json" =>
      "072f813ca1c696831a7f2fbd934feaa8cad228a6b3d44a4be8877547c796341b",
    "v2/NullableGetAccountTokenUsageParams.json" =>
      "a992c6ea0fe02b0e9f46b18afb51b8ee2635e7f0c7d546f71e7f95e2a98bebba",
    "v2/GetAccountRateLimitsResponse.json" =>
      "cb9655e68130116f634ed9353e45b336492e6069a6628f424d1cd52e54eda0e0",
    "v2/GetAccountTokenUsageResponse.json" =>
      "a58e58c852c888e5de925d99a66688d55ebb2fff038e795aadf04f8a8426dff8",
    "v2/GetWorkspaceMessagesResponse.json" =>
      "3ebd00f0acca088e5ee0309ec09b9a571e7f2eea5b63a32cda67be01c6886d67"
  }
  @id_bytes """
  {
    "$ref": "#/definitions/RequestId"
  }
  """
  @id_sha "f1fb3724bb7835add8ed79ef8a7e1acaf3c9c5761502e6ae54c85d0c7f6c82e7"
  @thread_bytes """
  {
    "description": "When present, read estimated usage for this thread instead of account-wide token activity.",
    "type": [
      "string",
      "null"
    ]
  }
  """
  @thread_sha "21343282c7ad507512e2b0518c6801089855cb89a1f837154940ec24c35a4a4f"
  @usage_params_object_bytes """
  {
    "$ref": "#/definitions/GetAccountTokenUsageParams"
  }
  """
  @usage_params_object_sha "27d4d860d2c08fc99eb29b6c45ea45f1b13831a0f133e9a4eced8bc02fd54843"
  @usage_null_bytes """
  {
    "type": "null"
  }
  """
  @usage_null_sha "b7c373d0981a5441c9dd775ad89a68ba691af04e4da70eaeaacaaf54549837fb"
  @usage_usd_bytes """
  {
    "format": "int64",
    "type": [
      "integer",
      "null"
    ]
  }
  """
  @usage_usd_sha "b9a3cfaac4768ba6031b3becb339a37683efd1eb4a6ec6128214bc7074bf2801"
  @rate_null_bytes """
  {
    "type": "null"
  }
  """
  @rate_null_sha "b7c373d0981a5441c9dd775ad89a68ba691af04e4da70eaeaacaaf54549837fb"
  @thread "019fc8ab-1fb2-7000-8000-000000000211"
  @rate "account/rateLimits/read"
  @usage "account/usage/read"
  @messages "account/workspaceMessages/read"
  @ids %{
    rate: [1_005_001, "1005001"],
    thread: [-211, "-211"],
    profile: [1_017_001, "1017001"],
    messages: [1_024_001, "1024001"]
  }

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
            {:error, failure} -> {:error, failure, next}
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
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    defp record_events(state, events) do
      Enum.reduce_while(events, :ok, fn
        {:message, encoded}, :ok ->
          case record(state, :in, encoded) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end

        _, :ok ->
          {:cont, :ok}
      end)
    end

    defp record(state, direction, encoded) do
      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(encoded)
        limit = if direction == :out, do: 8192, else: 131_072

        if length(ledger.frames) < 128 and size <= limit and ledger.bytes + size <= 1_048_576 do
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

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) === @binary_sha

    for {path, expected} <- [{@script, @script_sha}, {@base, @base_sha}, {@cleanup, @cleanup_sha}],
        do: assert(hash(File.read!(path)) === expected)

    for {name, expected} <- @schemas,
        do: assert(hash(File.read!(schema_path(name))) === expected)

    python = System.find_executable("python3") || flunk("BLOCKED_ENV: Python 3 required")

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-ordinary-read-" <>
          Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      )

    File.mkdir!(root)
    resources = :atomics.new(3, [])

    on_exit(fn ->
      assert Enum.all?(1..3, &(:atomics.get(resources, &1) in [0, 2])),
             "Owned cleanup unconfirmed; retaining ordinary data fixture #{root}"

      File.rm_rf!(root)
    end)

    for name <- ~w(home codex workspace tmp bin), do: File.mkdir!(Path.join(root, name))
    File.cp!("/bin/sh", Path.join(root, "bin/sh"))

    ctx = %{
      root: root,
      home: Path.join(root, "home"),
      codex: Path.join(root, "codex"),
      workspace: Path.join(root, "workspace"),
      bin: Path.join(root, "bin"),
      requests: Path.join(root, "requests.json"),
      python: python,
      binary: Path.expand(binary),
      capture: start_supervised!({Agent, fn -> %{frames: [], bytes: 0} end}),
      scenario:
        if(tags[:ordinary_null_rate],
          do: "ordinary-account-null-rate",
          else: "ordinary-account-read-metadata"
        ),
      resources: resources
    }

    provider = start_provider(ctx)

    paths =
      [
        @script,
        @base,
        @cleanup,
        ctx.requests,
        Path.join(ctx.bin, "sh"),
        Path.join(ctx.codex, "config.toml"),
        Path.join(ctx.codex, "models.json")
      ] ++
        Enum.map(Map.keys(@schemas), &schema_path/1)

    Map.merge(ctx, %{provider: provider, inputs: Map.new(paths, &{&1, snapshot(&1)})})
  end

  test "ordinary native data reads preserve thread reference and physical typed request IDs across cold sessions",
       ctx do
    deadline = now() + 30_000
    warm = start_native(ctx, 2)
    read_data(ctx, warm.pid, 0)
    assert_idle(warm.pid)
    assert_controls(ctx)
    prefix = frames(ctx)
    close_native(warm)
    cold = start_native(ctx, 3)
    assert cold.native !== warm.native and cold.instance !== warm.instance
    assert Enum.take(frames(ctx), length(prefix)) === prefix
    read_data(ctx, cold.pid, 1)
    assert_idle(cold.pid)
    assert_controls(ctx)
    assert_physical_owners(ctx)
    assert_backend(ctx)
    assert_inventory(ctx)
    assert now() < deadline
    close_native(cold)
    assert Enum.take(frames(ctx), length(prefix)) === prefix
    close_provider(ctx.provider)
    assert_controls(ctx)

    assert rows(ctx, "fixture_closed") === [
             %{"event" => "fixture_closed", "pid" => ctx.provider.native}
           ]
  end

  @tag :ordinary_null_rate
  test "ordinary rate read forwards physical root145 params null across cold sessions", ctx do
    deadline = now() + 30_000
    warm = start_native(ctx, 2)
    null_rate_data(ctx, warm.pid, Enum.at(@ids.rate, 0))
    assert_empty_loaded(ctx, warm.pid)
    assert_idle(warm.pid)
    assert_controls(ctx)
    prefix = frames(ctx)
    close_native(warm)
    cold = start_native(ctx, 3)
    assert cold.native !== warm.native and cold.instance !== warm.instance
    assert Enum.take(frames(ctx), length(prefix)) === prefix
    null_rate_data(ctx, cold.pid, Enum.at(@ids.rate, 1))
    assert_empty_loaded(ctx, cold.pid)
    assert_idle(cold.pid)
    assert_controls(ctx)
    assert_null_rate_owner(ctx)
    assert_null_rate_backend(ctx)
    assert_null_rate_inventory(ctx)
    assert now() < deadline
    close_native(cold)
    assert Enum.take(frames(ctx), length(prefix)) === prefix
    close_provider(ctx.provider)
    assert_controls(ctx)

    assert rows(ctx, "fixture_closed") === [
             %{"event" => "fixture_closed", "pid" => ctx.provider.native}
           ]
  end

  defp null_rate_data(ctx, pid, id) do
    result = call(ctx, pid, @rate, nil, id)

    # Numeric quota metadata only; all other account result fields stay opaque.
    assert Map.take(Map.fetch!(result, "rateLimits"), ["primary", "secondary"]) === %{
             "primary" => %{
               "usedPercent" => 37,
               "windowDurationMins" => 60,
               "resetsAt" => 2_000_000_100
             },
             "secondary" => %{
               "usedPercent" => 12,
               "windowDurationMins" => 1440,
               "resetsAt" => 2_000_000_200
             }
           }
  end

  defp assert_null_rate_owner(ctx) do
    root = schema("ClientRequest.json")
    selected = root |> Map.fetch!("oneOf") |> Enum.at(145)
    assert get_in(selected, ["properties", "method", "enum"]) === [@rate]
    node = selected |> get_in(["properties", "params", "anyOf"]) |> Enum.at(1)
    assert node === JSON.decode!(@rate_null_bytes)
    assert hash(@rate_null_bytes) === @rate_null_sha
    assert node === %{"type" => "null"}
    sent = Enum.filter(frames(ctx), &(&1.direction === :out and &1.wire["method"] === @rate))
    assert Enum.map(sent, & &1.wire["id"]) === @ids.rate

    for frame <- sent do
      assert Map.fetch!(frame.wire, "params") === nil

      assert frame.encoded ===
               JSON.encode!(%{"id" => frame.wire["id"], "method" => @rate, "params" => nil})

      assert :ok = Schema.validate(node, Map.fetch!(frame.wire, "params"))

      assert :ok =
               Schema.validate(Map.put(selected, "definitions", root["definitions"]), frame.wire,
                 max_depth: 64
               )

      assert :ok = Schema.validate(root, frame.wire, max_depth: 64)

      assert [reply] =
               Enum.filter(
                 frames(ctx),
                 &(&1.direction === :in and &1.wire["id"] === frame.wire["id"])
               )

      assert_exchange(ctx, frame.wire, reply.wire)
    end
  end

  defp assert_null_rate_backend(ctx) do
    expected =
      for sequence <- [1, 2],
          {kind, path} <- [
            {"rates", "/backend-api/wham/usage"},
            {"rate_details", "/backend-api/wham/rate-limit-reset-credits"}
          ],
          do: %{
            "event" => "business_read",
            "kind" => kind,
            "sequence" => sequence,
            "method" => "GET",
            "path" => path,
            "query" => %{},
            "status" => 200
          }

    # Stock tokio::join! makes sibling GET arrival order unspecified.
    sort = fn rows -> Enum.sort_by(rows, &{&1["sequence"], &1["kind"]}) end
    assert sort.(rows(ctx, "business_read")) === sort.(expected)

    rate_rows =
      for sequence <- [1, 2],
          do: %{
            "event" => "rate_data",
            "sequence" => sequence,
            "primary_percent" => 37,
            "primary_seconds" => 3600,
            "primary_reset" => 2_000_000_100,
            "secondary_percent" => 12,
            "secondary_seconds" => 86_400,
            "secondary_reset" => 2_000_000_200
          }

    assert rows(ctx, "rate_data") === rate_rows

    for event <- ~w(profile_data thread_data message_data), do: assert(rows(ctx, event) === [])

    assert Enum.all?(
             rows(ctx, "startup_read"),
             &(&1["query"] === %{} and
                 &1["path"] in [
                   "/backend-api/wham/config/bundle",
                   "/backend-api/wham/accounts/check",
                   "/backend-api/wham/settings/user"
                 ])
           )
  end

  defp assert_null_rate_inventory(ctx) do
    outgoing = Enum.filter(frames(ctx), &(&1.direction === :out))

    per_session = [
      "initialize",
      "initialized",
      "server/diagnostics",
      "thread/loaded/list",
      @rate,
      "thread/loaded/list"
    ]

    assert Enum.map(outgoing, & &1.wire["method"]) === per_session ++ per_session
    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 10 and length(Enum.uniq(ids)) === 10
    incoming = Enum.filter(frames(ctx), &(&1.direction === :in))
    replies = Enum.filter(incoming, &Map.has_key?(&1.wire, "id"))
    assert length(replies) === 10
    assert MapSet.new(Enum.map(replies, & &1.wire["id"])) === MapSet.new(ids)

    for notice <- Enum.reject(incoming, &Map.has_key?(&1.wire, "id")) do
      assert {:ok, decoded} = Wire.decode(notice.encoded, max_depth: 64)
      assert decoded === notice.wire
      refute String.starts_with?(Map.fetch!(notice.wire, "method"), ["thread/", "turn/", "item/"])
    end
  end

  defp read_data(ctx, pid, generation) do
    # Fixed detail-fetch setup only; no credit/reserve/account/permission field is inspected.
    rates =
      call(
        ctx,
        pid,
        @rate,
        %{"excludeResetCreditDetails" => true},
        Enum.at(@ids.rate, generation)
      )

    assert Map.take(Map.fetch!(rates, "rateLimits"), ["primary", "secondary"]) === %{
             "primary" => %{
               "usedPercent" => 37,
               "windowDurationMins" => 60,
               "resetsAt" => 2_000_000_100
             },
             "secondary" => %{
               "usedPercent" => 12,
               "windowDurationMins" => 1440,
               "resetsAt" => 2_000_000_200
             }
           }

    thread = call(ctx, pid, @usage, %{"threadId" => @thread}, Enum.at(@ids.thread, generation))

    assert Map.fetch!(thread, "threadUsage") === %{
             "threadId" => @thread,
             "estimatedUsageCreditsMicros" => 46_000_000,
             "estimatedUsageUsdMicros" => 2_500_000,
             "groups" => [
               %{
                 "model" => "owned-descriptive-model-λ",
                 "reasoningEffort" => "high",
                 "speed" => "standard",
                 "estimatedUsageCreditsMicros" => 46_000_000,
                 "netNewInputTokens" => 80,
                 "cachedInputTokens" => 20,
                 "inputTokens" => 100,
                 "outputTokens" => 40,
                 "totalTokens" => 140
               }
             ]
           }

    profile = call(ctx, pid, @usage, nil, Enum.at(@ids.profile, generation))
    assert Map.take(profile, ["summary", "dailyUsageBuckets"]) === expected_profile(generation)
    messages = call(ctx, pid, @messages, nil, Enum.at(@ids.messages, generation))

    assert Map.fetch!(messages, "messages") === [
             %{
               "messageId" => "owned-headline-1024",
               "messageType" => "headline",
               "messageBody" => "Owned ordinary headline λ🙂",
               "createdAt" => 100,
               "archivedAt" => 200
             },
             %{
               "messageId" => "owned-announcement-1024",
               "messageType" => "announcement",
               "messageBody" => "Owned descriptive announcement β🙂",
               "createdAt" => 300,
               "archivedAt" => nil
             }
           ]

    assert_empty_loaded(ctx, pid)
  end

  defp expected_profile(0),
    do: %{
      "summary" => %{
        "lifetimeTokens" => 1234,
        "peakDailyTokens" => 345,
        "longestRunningTurnSec" => 67,
        "currentStreakDays" => 8,
        "longestStreakDays" => 9
      },
      "dailyUsageBuckets" => [
        %{"startDate" => "2026-10-26", "tokens" => 111},
        %{"startDate" => "2026-10-27", "tokens" => 222}
      ]
    }

  defp expected_profile(1),
    do: %{
      "summary" => %{
        "lifetimeTokens" => 2345,
        "peakDailyTokens" => 456,
        "longestRunningTurnSec" => 78,
        "currentStreakDays" => 9,
        "longestStreakDays" => 10
      },
      "dailyUsageBuckets" => [
        %{"startDate" => "2026-10-27", "tokens" => 333},
        %{"startDate" => "2026-10-28", "tokens" => 444}
      ]
    }

  defp assert_physical_owners(ctx) do
    root = schema("ClientRequest.json")
    variants = Map.fetch!(root, "oneOf")
    definitions = Map.fetch!(root, "definitions")
    node = get_in(definitions, ["GetAccountTokenUsageParams", "properties", "threadId"])
    assert node === JSON.decode!(@thread_bytes)
    assert hash(@thread_bytes) === @thread_sha

    assert node === %{
             "description" =>
               "When present, read estimated usage for this thread instead of account-wide token activity.",
             "type" => ["string", "null"]
           }

    forwarded =
      Enum.filter(
        frames(ctx),
        &(&1.direction === :out and
            &1.wire["method"] === @usage and &1.wire["params"] === %{"threadId" => @thread})
      )

    assert Enum.map(forwarded, & &1.wire["id"]) === @ids.thread

    for frame <- forwarded,
        do: assert(:ok = Schema.validate(node, frame.wire["params"]["threadId"]))

    for {method, index, ids} <- [
          {@rate, 145, @ids.rate},
          {@usage, 147, [-211, 1_017_001, "-211", "1017001"]},
          {@messages, 148, @ids.messages}
        ] do
      assert [selected] =
               Enum.filter(
                 variants,
                 &(get_in(&1, ["properties", "method", "enum"]) === [method])
               )

      assert selected === Enum.at(variants, index)
      id_node = get_in(selected, ["properties", "id"])
      assert id_node === %{"$ref" => "#/definitions/RequestId"}
      assert JSON.decode!(@id_bytes) === id_node and hash(@id_bytes) === @id_sha
      sent = Enum.filter(frames(ctx), &(&1.direction === :out and &1.wire["method"] === method))
      assert Enum.map(sent, & &1.wire["id"]) === ids

      for frame <- sent do
        assert :ok =
                 Schema.validate(Map.put(id_node, "definitions", definitions), frame.wire["id"])

        assert :ok =
                 Schema.validate(Map.put(selected, "definitions", definitions), frame.wire,
                   max_depth: 64
                 )

        assert :ok = Schema.validate(root, frame.wire, max_depth: 64)
      end
    end

    assert definitions["RequestId"] === %{
             "anyOf" => [
               %{"type" => "string"},
               %{"format" => "int64", "type" => "integer"}
             ]
           }

    assert_usage_context_owners(ctx)
  end

  defp assert_usage_context_owners(ctx) do
    params_root = schema("v2/NullableGetAccountTokenUsageParams.json")
    params_definitions = Map.fetch!(params_root, "definitions")
    [params_object, params_null] = Map.fetch!(params_root, "anyOf")
    result_root = schema("v2/GetAccountTokenUsageResponse.json")

    usd =
      get_in(result_root, ["definitions", "ThreadUsage", "properties", "estimatedUsageUsdMicros"])

    [_, thread_usage_null] = get_in(result_root, ["properties", "threadUsage", "anyOf"])

    # Each tuple selects its own physical standalone request/output node.
    # Equal null-node hashes confer no credit on another operation or alias.
    for {node, bytes, sha} <- [
          {params_object, @usage_params_object_bytes, @usage_params_object_sha},
          {params_null, @usage_null_bytes, @usage_null_sha},
          {usd, @usage_usd_bytes, @usage_usd_sha},
          {thread_usage_null, @usage_null_bytes, @usage_null_sha}
        ] do
      assert node === JSON.decode!(bytes)
      assert hash(bytes) === sha
    end

    for id <- @ids.thread do
      {params, result} = captured_usage_exchange(ctx, id)
      assert params === %{"threadId" => @thread}
      assert :ok = Schema.validate(params_root, params, max_depth: 16)

      assert :ok =
               Schema.validate(Map.put(params_object, "definitions", params_definitions), params,
                 max_depth: 16
               )

      actual_usd = result |> Map.fetch!("threadUsage") |> Map.fetch!("estimatedUsageUsdMicros")
      assert actual_usd === 2_500_000
      assert :ok = Schema.validate(usd, actual_usd)
    end

    for {id, generation} <- Enum.with_index(@ids.profile) do
      {params, result} = captured_usage_exchange(ctx, id)
      assert params === nil
      assert :ok = Schema.validate(params_root, params, max_depth: 16)
      assert :ok = Schema.validate(params_null, params)
      assert Map.take(result, ["summary", "dailyUsageBuckets"]) === expected_profile(generation)
      actual_thread_usage = Map.fetch!(result, "threadUsage")
      assert actual_thread_usage === nil
      assert :ok = Schema.validate(thread_usage_null, actual_thread_usage)
    end
  end

  defp captured_usage_exchange(ctx, id) do
    assert [sent] =
             Enum.filter(
               frames(ctx),
               &(&1.direction === :out and &1.wire["method"] === @usage and &1.wire["id"] === id)
             )

    assert [received] =
             Enum.filter(frames(ctx), &(&1.direction === :in and &1.wire["id"] === id))

    assert_exchange(ctx, sent.wire, received.wire)
    {Map.fetch!(sent.wire, "params"), Map.fetch!(received.wire, "result")}
  end

  defp assert_backend(ctx) do
    expected =
      for sequence <- [1, 2],
          {kind, method, path} <- [
            {"rates", "GET", "/backend-api/wham/usage"},
            {"thread", "POST", "/backend-api/wham/usage/thread_usage/query"},
            {"profile", "GET", "/backend-api/wham/profiles/me"},
            {"messages", "GET", "/backend-api/wham/workspace-messages"}
          ] do
        base = %{
          "event" => "business_read",
          "kind" => kind,
          "sequence" => sequence,
          "method" => method,
          "path" => path,
          "query" => %{},
          "status" => 200
        }

        if kind == "thread",
          do: Map.put(base, "request_body", %{"thread_ids" => [@thread]}),
          else: base
      end

    assert rows(ctx, "business_read") === expected

    rate_rows =
      for sequence <- [1, 2],
          do: %{
            "event" => "rate_data",
            "sequence" => sequence,
            "primary_percent" => 37,
            "primary_seconds" => 3600,
            "primary_reset" => 2_000_000_100,
            "secondary_percent" => 12,
            "secondary_seconds" => 86_400,
            "secondary_reset" => 2_000_000_200
          }

    assert rows(ctx, "rate_data") === rate_rows

    assert rows(ctx, "profile_data") === [
             %{
               "event" => "profile_data",
               "sequence" => 1,
               "body" => %{
                 "stats" => %{
                   "lifetime_tokens" => 1234,
                   "peak_daily_tokens" => 345,
                   "longest_running_turn_sec" => 67,
                   "current_streak_days" => 8,
                   "longest_streak_days" => 9,
                   "daily_usage_buckets" => [
                     %{"start_date" => "2026-10-26", "tokens" => 111},
                     %{"start_date" => "2026-10-27", "tokens" => 222}
                   ]
                 }
               }
             },
             %{
               "event" => "profile_data",
               "sequence" => 2,
               "body" => %{
                 "stats" => %{
                   "lifetime_tokens" => 2345,
                   "peak_daily_tokens" => 456,
                   "longest_running_turn_sec" => 78,
                   "current_streak_days" => 9,
                   "longest_streak_days" => 10,
                   "daily_usage_buckets" => [
                     %{"start_date" => "2026-10-27", "tokens" => 333},
                     %{"start_date" => "2026-10-28", "tokens" => 444}
                   ]
                 }
               }
             }
           ]

    thread_body = %{
      "threads" => [
        %{
          "thread_id" => @thread,
          "estimated_usage_credits_micros" => 46_000_000,
          "estimated_usage_usd_micros" => 2_500_000,
          "native_usage_usd_micros" => 2_000_000,
          "groups" => [
            %{
              "model" => "owned-descriptive-model-λ",
              "reasoning_effort" => "high",
              "speed" => "standard",
              "estimated_usage_credits_micros" => 46_000_000,
              "native_usage_usd_micros" => 2_000_000,
              "net_new_input_tokens" => 80,
              "cached_input_tokens" => 20,
              "input_tokens" => 100,
              "output_tokens" => 40,
              "total_tokens" => 140
            }
          ]
        }
      ]
    }

    thread_rows =
      for sequence <- [1, 2],
          do: %{"event" => "thread_data", "sequence" => sequence, "body" => thread_body}

    assert rows(ctx, "thread_data") === thread_rows

    message_body = %{
      "messages" => [
        %{
          "message_id" => "owned-headline-1024",
          "message_type" => "headline",
          "message_body" => "Owned ordinary headline λ🙂",
          "created_at" => "1970-01-01T00:01:40Z",
          "archived_at" => "1970-01-01T01:03:20+01:00"
        },
        %{
          "message_id" => "owned-announcement-1024",
          "message_type" => "announcement",
          "message_body" => "Owned descriptive announcement β🙂",
          "created_at" => "1970-01-01T00:05:00Z",
          "archived_at" => nil
        }
      ]
    }

    message_rows =
      for sequence <- [1, 2],
          do: %{"event" => "message_data", "sequence" => sequence, "body" => message_body}

    assert rows(ctx, "message_data") === message_rows

    assert Enum.all?(
             rows(ctx, "startup_read"),
             &(&1["query"] === %{} and
                 &1["path"] in [
                   "/backend-api/wham/config/bundle",
                   "/backend-api/wham/accounts/check",
                   "/backend-api/wham/settings/user"
                 ])
           )
  end

  defp assert_inventory(ctx) do
    outgoing = Enum.filter(frames(ctx), &(&1.direction === :out))

    per_session = [
      "initialize",
      "initialized",
      "server/diagnostics",
      "thread/loaded/list",
      @rate,
      @usage,
      @usage,
      @messages,
      "thread/loaded/list"
    ]

    assert Enum.map(outgoing, & &1.wire["method"]) === per_session ++ per_session
    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 16 and length(Enum.uniq(ids)) === 16
    incoming = Enum.filter(frames(ctx), &(&1.direction === :in))
    responses = Enum.filter(incoming, &Map.has_key?(&1.wire, "id"))
    assert length(responses) === 16
    assert MapSet.new(Enum.map(responses, & &1.wire["id"])) === MapSet.new(ids)

    for notice <- Enum.reject(incoming, &Map.has_key?(&1.wire, "id")) do
      assert {:ok, decoded} = Wire.decode(notice.encoded, max_depth: 64)
      assert decoded === notice.wire
      refute String.starts_with?(Map.fetch!(notice.wire, "method"), ["thread/", "turn/", "item/"])
    end
  end

  defp start_provider(ctx) do
    assert {:ok, transport} =
             Stdio.open(
               executable: ctx.python,
               args: [
                 @script,
                 "--codex-home",
                 ctx.codex,
                 "--workspace",
                 ctx.workspace,
                 "--requests-file",
                 ctx.requests,
                 "--scenario",
                 ctx.scenario
               ],
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
    startup = provider_startup(transport.port, <<>>, now() + 5_000)
    native = startup["pid"]
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === hash(File.read!(ctx.python))
    assert is_binary(startup["url"]) and String.starts_with?(startup["url"], "http://127.0.0.1:")

    %{
      transport: transport,
      identity: identity,
      native: native,
      resources: ctx.resources,
      resource_slot: 1
    }
  end

  defp provider_startup(port, bytes, deadline) do
    remaining = deadline - now()
    assert remaining > 0, "Owned ordinary data dependency startup deadline"
    assert byte_size(bytes) <= 8192

    case String.split(bytes, "\n", parts: 2) do
      [line, ""] ->
        JSON.decode!(line)

      [_line, _extra] ->
        flunk("Unexpected owned data dependency startup output")

      [_partial] ->
        receive do
          {^port, {:data, chunk}} -> provider_startup(port, bytes <> chunk, deadline)
          {^port, {:exit_status, status}} -> flunk("Owned data dependency startup exit #{status}")
        after
          remaining -> flunk("Owned data dependency startup deadline")
        end
    end
  end

  defp start_native(ctx, resource_slot) do
    args = NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"])

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
                    args: args,
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

    :atomics.put(ctx.resources, resource_slot, 1)
    %{connection: connection} = :sys.get_state(pid)
    identity = :atomics.new(1, [])

    native = %{
      pid: pid,
      connection: connection,
      identity: identity,
      resources: ctx.resources,
      resource_slot: resource_slot
    }

    on_exit(fn -> close_native(native) end)
    id = request_id()
    info = %{"name" => "owned_ordinary_account_read_metadata", "version" => "1"}
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

    os_pid = call(ctx, pid, "server/diagnostics", %{}, request_id())["process"]["id"]
    assert is_integer(os_pid) and os_pid > 0
    :atomics.put(identity, 1, os_pid)
    assert hash(File.read!("/proc/#{os_pid}/exe")) === @binary_sha
    assert_empty_loaded(ctx, pid)
    Map.merge(native, %{native: os_pid, instance: Session.status(pid).instance_id})
  end

  defp call(ctx, pid, method, params, id) do
    wire = %{"id" => id, "method" => method, "params" => params}
    assert :ok = Schema.validate(schema("ClientRequest.json"), wire, max_depth: 64)
    reply = Session.request_native(pid, wire, timeout_ms: 5_000)
    assert rows(ctx, "fixture_error") === [] and rows(ctx, "unexpected_http") === []
    assert {:ok, %{"id" => ^id, "result" => result} = response} = reply
    assert_exchange(ctx, wire, response)
    # Only selected descriptive data is an oracle. Do not validate opaque
    # account/permission/feature result fields as part of this ordinary profile.
    result
  end

  defp assert_exchange(ctx, wire, response) do
    assert [sent] =
             Enum.filter(frames(ctx), &(&1.direction === :out and &1.wire["id"] === wire["id"]))

    assert [received] =
             Enum.filter(frames(ctx), &(&1.direction === :in and &1.wire["id"] === wire["id"]))

    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert {:ok, decoded_request} = Wire.decode(sent.encoded, max_depth: 64)
    assert decoded_request === wire
    assert {:ok, decoded_response} = Wire.decode(received.encoded, max_depth: 64)
    assert decoded_response === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp assert_empty_loaded(ctx, pid),
    do:
      assert(
        call(ctx, pid, "thread/loaded/list", %{}, request_id()) === %{
          "data" => [],
          "nextCursor" => nil
        }
      )

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
    assert {:ok, events} = Session.drain(pid, 128)
    assert length(events) <= 128
    assert {:ok, []} = Session.drain(pid, 128)
  end

  defp assert_controls(ctx) do
    for {path, before} <- ctx.inputs, do: assert(snapshot(path) === before)
    assert File.read!(ctx.requests) |> JSON.decode!() === []
    assert File.ls!(ctx.workspace) === []
    assert Path.wildcard(Path.join(ctx.codex, "sessions/**/rollout-*.jsonl")) === []
    assert rows(ctx, "fixture_error") === [] and rows(ctx, "unexpected_http") === []
    assert Enum.all?(journal(ctx), &(&1["event"] in ~w(fixture_started fixture_closed
      startup_read business_read rate_data profile_data thread_data message_data)))
  end

  defp frames(ctx), do: Agent.get(ctx.capture, & &1.frames)
  defp rows(ctx, kind), do: Enum.filter(journal(ctx), &(&1["event"] === kind))

  defp journal(ctx) do
    bytes = snapshot(Path.join(ctx.root, "ordinary-account-read-metadata-journal.json")).bytes
    assert byte_size(bytes) <= 131_072
    events = JSON.decode!(bytes) |> Map.fetch!("events")
    assert length(events) <= 96
    events
  end

  defp close_native(native) do
    monitor = Process.monitor(native.connection.owner.pid)
    assert :ok = StdioSessionFixture.close(native.pid, native.connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert_closed(native.connection, native.identity)
    :atomics.put(native.resources, native.resource_slot, 2)
  end

  defp close_provider(provider),
    do:
      close_transport(
        provider.transport,
        provider.identity,
        provider.resources,
        provider.resource_slot
      )

  defp close_transport(connection, identity, resources, resource_slot) do
    monitor = Process.monitor(connection.owner.pid)
    assert :ok = Stdio.close(connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert_closed(connection, identity)
    :atomics.put(resources, resource_slot, 2)
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

  defp schema(name), do: schema_path(name) |> File.read!() |> JSON.decode!()

  defp schema_path(name),
    do:
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/" <> name)

  defp request_id, do: "owned-ordinary-read-#{System.unique_integer([:positive, :monotonic])}"
  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
