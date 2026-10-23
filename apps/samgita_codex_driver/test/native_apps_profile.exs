defmodule SamgitaCodexDriver.NativeAppsProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag :isolated_apps
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_apps_fixture.py", __DIR__)

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert System.find_executable("unshare"), "BLOCKED_ENV: unshare required"
    assert System.find_executable("ip"), "BLOCKED_ENV: ip required"

    root =
      Path.join(System.tmp_dir!(), "samgita-isolated-apps-#{System.unique_integer([:positive])}")

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      binary: binary,
      scenario: tags[:scenario] || "enabled",
      journal: Path.join(root, "isolated-apps-journal.json")
    }
  end

  test "native app metadata preserves first occurrence order and partial misses with scoped cache",
       ctx do
    pid = start(ctx)

    assert read(pid, ["beta", "missing", "alpha", "beta", "forbidden"], true) == %{
             "apps" => [metadata("beta", true), metadata("alpha", true)],
             "missingAppIds" => ["missing", "forbidden"]
           }

    assert batches(ctx) == [
             %{
               "app_ids" => ["beta", "missing", "alpha", "forbidden"],
               "include_tools" => true
             }
           ]

    assert read(pid, ["alpha", "beta"], true) == %{
             "apps" => [metadata("alpha", true), metadata("beta", true)],
             "missingAppIds" => []
           }

    assert length(batches(ctx)) == 1

    # An unsolicited backend record must not populate the requested cache scope.
    assert read(pid, ["extra"], true) == %{
             "apps" => [metadata("extra", true)],
             "missingAppIds" => []
           }

    assert length(batches(ctx)) == 2
    assert_profile(ctx, pid)
    close(ctx, pid)
  end

  test "metadata only cache refetches tools once and later hides unrequested tool summaries",
       ctx do
    pid = start(ctx)

    assert read(pid, ["alpha"], false) == %{
             "apps" => [metadata("alpha", false)],
             "missingAppIds" => []
           }

    assert read(pid, ["alpha"], true) == %{
             "apps" => [metadata("alpha", true)],
             "missingAppIds" => []
           }

    for include_tools <- [false, true] do
      assert read(pid, ["alpha"], include_tools) == %{
               "apps" => [metadata("alpha", include_tools)],
               "missingAppIds" => []
             }
    end

    assert batches(ctx) == [
             %{"app_ids" => ["alpha"], "include_tools" => false},
             %{"app_ids" => ["alpha"], "include_tools" => true}
           ]

    assert_profile(ctx, pid)
    close(ctx, pid)
  end

  test "backend failures including rate limits remain errors and retain prior fresh metadata",
       ctx do
    pid = start(ctx)
    cached = read(pid, ["alpha"], true)
    assert cached["apps"] == [metadata("alpha", true)]

    for status <- [500, 429] do
      set_status(ctx, status)
      error = upstream_error(pid, "app/read", params(["alpha", "uncached"], true))
      assert error["code"] == -32_603
      assert error["message"] =~ "failed to read app metadata"
      before_cached_read = length(batches(ctx))
      assert read(pid, ["alpha"], true) == cached
      assert length(batches(ctx)) == before_cached_read
    end

    set_status(ctx, 200)
    assert read(pid, ["beta"], true)["apps"] == [metadata("beta", true)]
    assert Enum.any?(events(ctx), &(&1["event"] == "batch" and &1["status"] == 429))
    assert_profile(ctx, pid)
    close(ctx, pid)
  end

  test "raw input limit precedes deduplication and unknown threads fail before backend access",
       ctx do
    pid = start(ctx)

    assert read(pid, [], false) == %{"apps" => [], "missingAppIds" => []}
    assert batches(ctx) == []

    assert upstream_error(pid, "app/read", params(List.duplicate("alpha", 101), false)) == %{
             "code" => -32_602,
             "message" => "app/read accepts at most 100 appIds"
           }

    error =
      upstream_error(
        pid,
        "app/read",
        Map.put(params(["alpha"], false), "threadId", "missing-native-thread")
      )

    assert error["code"] == -32_600
    assert error["message"] =~ "thread"
    assert batches(ctx) == []

    ids = Enum.map(1..100, &"missing-#{&1}")
    assert read(pid, ids, false) == %{"apps" => [], "missingAppIds" => ids}
    assert batches(ctx) == [%{"app_ids" => ids, "include_tools" => false}]
    assert_profile(ctx, pid)
    close(ctx, pid)
  end

  @tag scenario: "disabled"
  test "disabled apps retain deduplicated missing identities without backend access", ctx do
    pid = start(ctx)

    assert read(pid, ["alpha", "beta", "alpha"], true) == %{
             "apps" => [],
             "missingAppIds" => ["alpha", "beta"]
           }

    assert batches(ctx) == []
    assert_profile(ctx, pid)
    close(ctx, pid)
  end

  @tag scenario: "api_key"
  test "API key auth cannot substitute for hosted app backend auth", ctx do
    pid = start(ctx)

    assert read(pid, ["alpha", "alpha"], false) == %{
             "apps" => [],
             "missingAppIds" => ["alpha"]
           }

    assert batches(ctx) == []
    assert_profile(ctx, pid)
    close(ctx, pid)
  end

  @tag scenario: "custom_sku"
  test "configured product SKU reaches the native backend request without exposing credentials",
       ctx do
    pid = start(ctx)
    assert read(pid, ["beta"], true)["apps"] == [metadata("beta", true)]
    assert length(batches(ctx)) == 1
    assert_profile(ctx, pid)
    close(ctx, pid)
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
               %{"name" => "samgita_isolated_apps", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp read(pid, ids, tools), do: call(pid, "app/read", params(ids, tools))
  defp params(ids, tools), do: %{"appIds" => ids, "includeTools" => tools, "threadId" => nil}

  defp metadata(id, tools) do
    name = String.capitalize(id)

    %{
      "id" => id,
      "name" => name,
      "description" => "#{name} description",
      "iconUrl" => nil,
      "iconUrlDark" => "https://synthetic.invalid/icons/#{id}-dark",
      "distributionChannel" => "ECOSYSTEM_DIRECTORY",
      "installUrl" => "https://chatgpt.com/apps/#{id}/#{id}",
      "pluginDisplayNames" => [],
      "toolSummaries" =>
        if(tools,
          do: [
            %{
              "name" => "#{id}_tool",
              "title" => "#{name} Tool",
              "description" => "Use #{name}",
              "isEnabled" => false,
              "disabledReason" => "disabled_by_admin",
              "isReadOnly" => true
            }
          ],
          else: nil
        )
    }
  end

  defp set_status(ctx, status) do
    pending = Path.join(ctx.root, "status.pending")
    File.write!(pending, Integer.to_string(status))
    File.rename!(pending, Path.join(ctx.root, "status"))
  end

  defp assert_profile(ctx, pid) do
    data = journal(ctx)
    assert data["namespace"]["parent"] != data["namespace"]["child"]
    assert data["namespace"]["interfaces"] == ["lo"]
    refute data["namespace"]["default_route"]
    refute Enum.any?(data["events"], &(&1["event"] in ["unexpected_http", "fixture_error"]))

    assert Enum.all?(batches_with_metadata(ctx), fn event ->
             event["bearer_verified"] and event["account_verified"] and event["sku_verified"]
           end)

    assert call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert Session.status(pid).phase == :ready
    assert {:ok, native_events} = Session.drain(pid)
    refute Enum.any?(native_events, &(&1.kind == :server_request))
    refute Enum.any?(native_events, &String.starts_with?(&1.wire["method"] || "", "turn/"))

    auth = ctx.root |> Path.join("codex/auth.json") |> File.read!() |> JSON.decode!()
    secrets = Map.values(auth["tokens"] || %{}) ++ [auth["OPENAI_API_KEY"]]

    for path <- [ctx.journal, Path.join(ctx.root, "native-stderr.log")],
        secret <- secrets,
        is_binary(secret) and secret != "" do
      refute File.read!(path) =~ secret
    end
  end

  defp close(ctx, pid) do
    started = Enum.find(events(ctx), &(&1["event"] == "native_started"))
    assert :ok = Session.close(pid)

    for key <- ["pid", "controller_pid", "namespace_owner_pid"] do
      refute File.exists?("/proc/#{Map.fetch!(started, key)}"),
             "owned apps process must be reaped"
    end

    assert Enum.any?(events(ctx), &(&1["event"] == "native_closed"))
    refute Enum.any?(events(ctx), &(&1["event"] in ["unexpected_http", "fixture_error"]))
  end

  defp journal(ctx), do: ctx.journal |> File.read!() |> JSON.decode!()
  defp events(ctx), do: journal(ctx)["events"]
  defp batches_with_metadata(ctx), do: Enum.filter(events(ctx), &(&1["event"] == "batch"))
  defp batches(ctx), do: Enum.map(batches_with_metadata(ctx), & &1["body"])

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp upstream_error(pid, method, params) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             Session.request(pid, method, params)

    error
  end
end
