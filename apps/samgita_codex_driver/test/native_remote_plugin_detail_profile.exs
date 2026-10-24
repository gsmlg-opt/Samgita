defmodule SamgitaCodexDriver.NativeRemotePluginDetailProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_plugin_detail_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @remote "plugins~Plugin_owned_schedule"
  @params %{"remoteMarketplaceName" => "openai-curated-remote", "pluginName" => @remote}
  @days ~w(MO TU WE TH FR SA SU)

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ["python3", "unshare", "ip", "openssl"], do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-plugin-detail-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for dir <- ["home", "codex", "workspace", "tmp"], do: File.mkdir_p!(Path.join(root, dir))
    ctx = %{root: root, binary: Path.expand(binary)}

    write_state(ctx, %{
      "detail" => %{"body" => detail_body()},
      "installed" => %{"body" => %{"plugins" => [], "pagination" => %{"next_page_token" => nil}}}
    })

    # Keep deterministic evidence even if the body or shutdown callback fails.
    # Roots contain only owned synthetic credentials and fixture data.
    on_exit(fn -> IO.puts(:stderr, "Owned plugin detail evidence retained: #{root}") end)
    ctx
  end

  test "all four schedule variants survive authenticated native detail and cold reread", ctx do
    rows = [
      task("hourly", %{"type" => "hourly", "intervalHours" => 2, "days" => ["MO", "WE", "FR"]}),
      task("daily", %{"type" => "daily", "time" => "09:15"}),
      task("weekdays", %{"type" => "weekdays", "time" => "08:30"}),
      task("weekly", %{"type" => "weekly", "time" => "16:45", "days" => @days})
    ]

    put_schedules(ctx, rows)
    pid = start(ctx)
    assert schedules(pid) == rows
    assert schedules(pid) == rows
    assert_profile(ctx, pid)
    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert schedules(cold) == rows
    assert length(events(ctx, "detail")) == 3
    assert length(events(ctx, "installed")) == 3
    assert_profile(ctx, cold)
  end

  test "unavailable metadata stays null while an explicit empty collection stays empty", ctx do
    pid = start(ctx)
    assert schedules(pid) == nil
    put_schedules(ctx, nil)
    assert schedules(pid) == nil
    put_schedules(ctx, [])
    assert schedules(pid) == []
    put_schedules(ctx, [task("visible", %{"type" => "daily", "time" => "09:15"})])
    assert length(schedules(pid)) == 1
    put_detail(ctx, detail_body())
    assert schedules(pid) == nil
    assert_profile(ctx, pid)
  end

  test "native metadata retains u32 boundaries opaque times and ordered duplicate weekdays",
       ctx do
    pid = start(ctx)

    rows = [
      task("zero", %{"type" => "hourly", "intervalHours" => 0}),
      task("maximum", %{"type" => "hourly", "intervalHours" => 4_294_967_295, "days" => nil}),
      task("empty", %{"type" => "hourly", "intervalHours" => 2, "days" => []}),
      task("daily", %{"type" => "daily", "time" => "owned opaque time λ"}),
      task("weekdays", %{"type" => "weekdays", "time" => ""}),
      task("weekly", %{"type" => "weekly", "time" => "25:99", "days" => ["SU", "MO", "SU"]}),
      task("weekly-empty", %{"type" => "weekly", "time" => "00:00", "days" => []})
    ]

    put_schedules(ctx, rows)
    expected = List.update_at(rows, 0, &put_in(&1, ["schedule", "days"], nil))
    assert schedules(pid) == expected
    assert_profile(ctx, pid)
  end

  test "one malformed schedule rejects the complete native detail without partial or stale data",
       ctx do
    pid = start(ctx)
    valid = task("valid", %{"type" => "daily", "time" => "09:15"})

    for {schedule, diagnostic} <- [
          {%{"type" => "hourly", "intervalHours" => -1}, "expected u32"},
          {%{"type" => "hourly", "intervalHours" => 4_294_967_296}, "expected u32"},
          {%{"type" => "hourly"}, "missing field `intervalHours`"},
          {%{"type" => "daily"}, "missing field `time`"},
          {%{"type" => "weekdays", "time" => nil}, "expected a string"},
          {%{"type" => "weekly", "time" => "09:15", "days" => nil}, "expected a sequence"},
          {%{"type" => "weekly", "time" => "09:15", "days" => ["mo"]}, "unknown variant `mo`"},
          {%{"type" => "monthly", "time" => "09:15"}, "unknown variant `monthly`"}
        ] do
      put_schedules(ctx, [valid, task("invalid", schedule)])
      installed_before = length(events(ctx, "installed"))
      failure = error(pid)
      assert failure["code"] == -32_603

      assert failure["message"] =~
               "read remote plugin details: failed to parse remote plugin catalog response"

      assert failure["message"] =~ diagnostic
      assert length(events(ctx, "installed")) == installed_before
      put_schedules(ctx, [valid])
      assert schedules(pid) == [valid]
    end

    assert_profile(ctx, pid)
  end

  test "detail HTTP and authentication errors cannot become empty success", ctx do
    pid = start(ctx)

    for {status, code} <- [{404, -32_600}, {401, -32_603}, {429, -32_603}, {503, -32_603}] do
      put_resource(ctx, "detail", %{"status" => status})
      installed_before = length(events(ctx, "installed"))
      failure = error(pid)
      assert failure["code"] == code
      assert failure["message"] =~ "read remote plugin details:"
      assert failure["message"] =~ "failed with status #{status}"
      assert length(events(ctx, "installed")) == installed_before
    end

    put_detail(ctx, detail_body())
    assert schedules(pid) == nil
    assert_profile(ctx, pid)
    assert :ok = Session.close(pid)

    for auth <- ["none", "apikey"] do
      unauthenticated = start(ctx, auth)
      reads_before = length(events(ctx, "detail"))
      failure = error(unauthenticated)
      assert failure["code"] == -32_600

      expected =
        "read remote plugin details: chatgpt authentication required for remote plugin catalog"

      suffix = if auth == "apikey", do: "; api key auth is not supported", else: ""
      assert failure["message"] == expected <> suffix
      assert length(events(ctx, "detail")) == reads_before
      assert_profile(ctx, unauthenticated)
      assert :ok = Session.close(unauthenticated)
    end
  end

  defp start(ctx, auth \\ "chatgpt") do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: System.find_executable("python3"),
             args: [@script, "--root", ctx.root, "--codex", ctx.binary, "--auth", auth],
             cwd: Path.join(ctx.root, "workspace"),
             inherit_env: [],
             env: %{
               "HOME" => Path.join(ctx.root, "home"),
               "CODEX_HOME" => Path.join(ctx.root, "codex"),
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
               "PYTHONDONTWRITEBYTECODE" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    %{connection: connection} = :sys.get_state(pid)

    on_exit(fn ->
      StdioSessionFixture.close(pid, connection)
      assert_owned_processes_gone(ctx)
    end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_plugin_detail", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    namespace = journal(ctx)["namespace"]
    assert namespace["parent"] == File.read_link!("/proc/self/ns/net")
    assert namespace["child"] != namespace["parent"]
    assert namespace["interfaces"] == ["lo"] and namespace["default_route"] == false

    for key <- ["routes_v4", "routes_v6"] do
      assert is_list(namespace[key])
      assert Enum.all?(namespace[key], &(&1["dst"] != "default" and &1["dev"] == "lo"))
    end

    config = File.read!(Path.join(ctx.root, "codex/config.toml"))
    assert length(Regex.scan(~r/^cli_auth_credentials_store = "file"$/m, config)) == 1
    pid
  end

  defp detail_body do
    %{
      "id" => @remote,
      "name" => "owned-schedule",
      "scope" => "GLOBAL",
      "installation_policy" => "AVAILABLE",
      "authentication_policy" => "ON_USE",
      "release" => %{
        "version" => "1.0.0",
        "display_name" => "Owned schedule metadata",
        "description" => "Synthetic untrusted input only",
        "interface" => %{}
      }
    }
  end

  defp task(key, schedule),
    do: %{
      "key" => key,
      "name" => "Owned #{key}",
      "prompt" => "Untrusted owned metadata λ; never execute.",
      "schedule" => schedule
    }

  defp state(ctx), do: JSON.decode!(File.read!(Path.join(ctx.root, "detail-state.json")))

  defp write_state(ctx, value) do
    temporary = Path.join(ctx.root, "detail-state.pending")
    File.write!(temporary, JSON.encode!(value))
    File.rename!(temporary, Path.join(ctx.root, "detail-state.json"))
  end

  defp put_resource(ctx, key, value), do: write_state(ctx, Map.put(state(ctx), key, value))
  defp put_detail(ctx, body), do: put_resource(ctx, "detail", %{"body" => body})

  defp put_schedules(ctx, value),
    do: put_detail(ctx, put_in(detail_body(), ["release", "scheduled_tasks"], value))

  defp journal(ctx), do: JSON.decode!(File.read!(Path.join(ctx.root, "journal.json")))
  defp events(ctx, event), do: Enum.filter(journal(ctx)["events"], &(&1["event"] == event))
  defp read(pid), do: call(pid, "plugin/read", @params)["plugin"]

  defp schedules(pid) do
    plugin = read(pid)
    assert Map.has_key?(plugin, "scheduledTasks")
    plugin["scheduledTasks"]
  end

  defp call(pid, method, params) do
    case Session.request(pid, method, params) do
      {:ok, %{"result" => result}} ->
        result

      {:error, %Error{} = failure} ->
        flunk("Native #{method} #{failure.code}: #{inspect(failure.wire)}")
    end
  end

  defp error(pid) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => failure}}} =
             Session.request(pid, "plugin/read", @params)

    failure
  end

  defp assert_profile(ctx, pid) do
    assert call(pid, "thread/loaded/list", %{})["data"] == []
    assert events(ctx, "forbidden_http") == []
    assert events(ctx, "fixture_error") == []
    assert length(events(ctx, "plugin_startup_disabled")) == length(events(ctx, "native_started"))
    assert length(events(ctx, "plugin_requests_enabled")) == length(events(ctx, "native_started"))

    for event <- events(ctx, "detail") ++ events(ctx, "installed"),
        do:
          assert(
            event["bearer_verified"] and event["account_verified"] and event["product_verified"]
          )

    for event <- events(ctx, "detail"), do: assert(event["query"] == %{})

    for event <- events(ctx, "installed") do
      assert event["query"] == %{"scope" => ["GLOBAL"]}
    end
  end

  defp assert_owned_processes_gone(ctx) do
    for event <- events(ctx, "native_started"),
        key <- ["pid", "controller_pid", "namespace_owner_pid"],
        do: await(fn -> not File.exists?("/proc/#{event[key]}") end)

    assert length(events(ctx, "native_closed")) == length(events(ctx, "native_started"))
  end

  defp await(predicate, remaining \\ 500)

  defp await(predicate, remaining) when remaining > 0 do
    if predicate.(),
      do: :ok,
      else:
        (
          Process.sleep(10)
          await(predicate, remaining - 1)
        )
  end

  defp await(_predicate, 0), do: flunk("owned plugin detail process was not reaped")
end
