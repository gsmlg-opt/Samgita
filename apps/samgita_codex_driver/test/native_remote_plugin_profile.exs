defmodule SamgitaCodexDriver.NativeRemotePluginProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_remote_plugin_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @remote "plugins~Plugin_fixture_remote"
  @id "fixture-remote@openai-curated-remote"
  @skill %{
    "remoteMarketplaceName" => "openai-curated-remote",
    "remotePluginId" => @remote,
    "skillName" => "inspect"
  }

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ["python3", "unshare", "ip", "openssl"], do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-remote-plugin-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for dir <- ["home", "codex", "workspace", "tmp"], do: File.mkdir_p!(Path.join(root, dir))
    on_exit(fn -> File.rm_rf!(root) end)
    ctx = %{root: root, binary: Path.expand(binary)}

    write_state(ctx, %{
      "skill" => %{"status" => 200, "body" => skill_body("# Synthetic remote skill\n")},
      "installed" => %{"status" => 200, "plugins" => []},
      "bundles" => %{"first" => %{"capabilities" => ["skills"], "marker" => "first"}}
    })

    ctx
  end

  test "authenticated skill read preserves matching Unicode contents and explicit null", ctx do
    pid = start(ctx)

    for contents <- ["# Owned skill\n\nUntrusted text λ 日本語", nil] do
      put_resource(ctx, "skill", %{"status" => 200, "body" => skill_body(contents)})
      assert call(pid, "plugin/skill/read", @skill) == %{"contents" => contents}
    end

    assert Enum.all?(
             events(ctx, "skill"),
             &(&1["path"] == "/backend-api/ps/plugins/#{@remote}/skills/inspect")
           )

    assert length(events(ctx, "skill")) == 2
    assert events(ctx, "bundle") == []
    assert_profile(ctx, pid)
  end

  test "skill response identity and JSON failures stay errors rather than fabricated contents",
       ctx do
    pid = start(ctx)

    for {body, fragment} <- [
          {Map.put(skill_body("wrong plugin"), "plugin_id", "plugins~Other"),
           "unexpected plugin id"},
          {Map.put(skill_body("wrong name"), "name", "other-skill"), "unexpected skill name"}
        ] do
      put_resource(ctx, "skill", %{"status" => 200, "body" => body})
      failure = error(pid, "plugin/skill/read", @skill)
      assert failure["code"] == -32_603
      assert failure["message"] =~ fragment
    end

    put_resource(ctx, "skill", %{"status" => 200, "raw" => "synthetic invalid JSON"})
    failure = error(pid, "plugin/skill/read", @skill)
    assert failure["code"] == -32_603
    assert failure["message"] =~ "failed to parse remote plugin catalog response"
    assert_profile(ctx, pid)
  end

  test "skill HTTP authorization absence rate limits and missing metadata remain explicit errors",
       ctx do
    pid = start(ctx)

    for {status, code} <- [{404, -32_600}, {401, -32_603}, {429, -32_603}, {503, -32_603}] do
      put_resource(ctx, "skill", %{"status" => status})
      failure = error(pid, "plugin/skill/read", @skill)
      assert failure["code"] == code
      assert failure["message"] =~ "failed with status #{status}"
      assert List.last(events(ctx, "skill"))["status"] == status
    end

    assert_profile(ctx, pid)
    assert :ok = Session.close(pid)

    for auth <- ["none", "apikey"] do
      unauthenticated = start(ctx, auth: auth)
      before_reads = length(events(ctx, "skill"))
      failure = error(unauthenticated, "plugin/skill/read", @skill)
      assert failure["code"] == -32_600
      assert failure["message"] =~ "chatgpt authentication required"
      assert length(events(ctx, "skill")) == before_reads
      assert_profile(ctx, unauthenticated)
      assert :ok = Session.close(unauthenticated)
    end
  end

  test "HTTPS materialization reports declarations then reuses bundle across repeats and cold restart",
       ctx do
    caps = ~w(skills mcps apps hooks)
    put_bundle(ctx, "first", %{"capabilities" => caps, "marker" => "first"})
    snapshot(ctx, [%{"bundle" => "first"}])
    pid = start(ctx)
    assert reconcile(pid) == result([change(@id, caps)])
    assert_bundle(ctx, "fixture-remote", "1.0.0", "first")
    assert length(events(ctx, "bundle")) == 1
    assert reconcile(pid) == result([])
    assert length(events(ctx, "bundle")) == 1
    assert_profile(ctx, pid)
    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert reconcile(cold) == result([])
    assert_bundle(ctx, "fixture-remote", "1.0.0", "first")
    assert length(events(ctx, "bundle")) == 1
    assert_profile(ctx, cold)
    assert Enum.all?(events(ctx, "native_started"), &(&1["trust_env"] == "CODEX_CA_CERTIFICATE"))
  end

  test "revision changes union old and new declarations while disablement and removal retain hints",
       ctx do
    initial_caps = ~w(skills mcps)
    next_caps = ~w(apps hooks)
    put_bundle(ctx, "first", %{"capabilities" => initial_caps, "marker" => "first"})
    put_bundle(ctx, "second", %{"capabilities" => next_caps, "marker" => "second"})
    snapshot(ctx, [%{"bundle" => "first"}])
    pid = start(ctx)
    assert reconcile(pid) == result([change(@id, initial_caps)])
    snapshot(ctx, [%{"version" => "2.0.0", "bundle" => "second"}])
    assert reconcile(pid) == result([change(@id, initial_caps ++ next_caps)])
    assert_bundle(ctx, "fixture-remote", "2.0.0", "second")
    downloads = length(events(ctx, "bundle"))

    for enabled <- [false, true] do
      snapshot(ctx, [%{"version" => "2.0.0", "bundle" => "second", "enabled" => enabled}])
      assert reconcile(pid) == result([change(@id, next_caps)])
      assert length(events(ctx, "bundle")) == downloads
    end

    snapshot(ctx, [])
    assert reconcile(pid) == result([change(@id, next_caps)])
    refute File.exists?(plugin_base(ctx, "fixture-remote"))
    assert reconcile(pid) == result([])
    assert_profile(ctx, pid)
  end

  test "per-plugin validation and archive failures coexist with success using SSL_CERT_FILE trust",
       ctx do
    bad_ids = ~w(plugins~MissingVersion plugins~HttpBundle plugins~BadArchive)
    put_bundle(ctx, "invalid", %{"invalid_archive" => true})

    snapshot(ctx, [
      %{"bundle" => "first"},
      %{
        "id" => Enum.at(bad_ids, 0),
        "name" => "missing-version",
        "release" => %{"version" => nil}
      },
      %{
        "id" => Enum.at(bad_ids, 1),
        "name" => "http-bundle",
        "release" => %{"bundle_download_url" => "http://127.0.0.1:1/not-permitted"}
      },
      %{"id" => Enum.at(bad_ids, 2), "name" => "bad-archive", "bundle" => "invalid"}
    ])

    pid = start(ctx, trust_env: "SSL_CERT_FILE")
    assert reconcile(pid) == result([change(@id, ["skills"])], Enum.sort(bad_ids))
    assert_bundle(ctx, "fixture-remote", "1.0.0", "first")

    for name <- ~w(missing-version http-bundle bad-archive),
        do: refute(File.exists?(version(ctx, name, "1.0.0")))

    assert Enum.sort(Enum.map(events(ctx, "bundle"), & &1["key"])) == ["first", "invalid"]
    assert_profile(ctx, pid)
    assert List.last(events(ctx, "native_started"))["trust_env"] == "SSL_CERT_FILE"
  end

  test "whole snapshot HTTP decode and invalid identity failures abort without deleting cached bundle",
       ctx do
    snapshot(ctx, [%{}])
    pid = start(ctx)
    assert reconcile(pid) == result([change(@id, ["skills"])])
    downloads = length(events(ctx, "bundle"))

    for status <- [401, 429, 503] do
      put_resource(ctx, "installed", %{"status" => status})
      failure = error(pid, "plugin/reconcile", %{"reason" => "synthetic-backend-failure"})
      assert failure["code"] == -32_603
      assert failure["message"] =~ "failed to reconcile remote installed plugins"
      assert failure["message"] =~ "failed with status #{status}"
      assert_bundle(ctx, "fixture-remote", "1.0.0", "first")
    end

    put_resource(ctx, "installed", %{"status" => 200, "raw" => "invalid snapshot JSON"})
    failure = error(pid, "plugin/reconcile", %{})
    assert failure["code"] == -32_603
    assert failure["message"] =~ "failed to parse remote plugin catalog response"
    # The name is rejected before joining cache paths; no tar traversal fixture is used.
    snapshot(ctx, [%{"name" => "invalid plugin name"}])
    failure = error(pid, "plugin/reconcile", %{})
    assert failure["code"] == -32_603
    assert failure["message"] =~ "invalid"
    assert_bundle(ctx, "fixture-remote", "1.0.0", "first")
    assert length(events(ctx, "bundle")) == downloads
    assert_profile(ctx, pid)
  end

  test "failed newer bundle preserves usable old version and later recovery reports unioned changes",
       ctx do
    snapshot(ctx, [%{}])
    pid = start(ctx)
    assert reconcile(pid) == result([change(@id, ["skills"])])

    put_bundle(ctx, "second", %{"status" => 503, "marker" => "second", "capabilities" => ["apps"]})

    snapshot(ctx, [%{"version" => "2.0.0", "bundle" => "second"}])
    assert reconcile(pid) == result([], [@remote])
    assert_bundle(ctx, "fixture-remote", "1.0.0", "first")
    refute File.exists?(version(ctx, "fixture-remote", "2.0.0"))
    assert List.last(events(ctx, "bundle"))["status"] == 503

    put_bundle(ctx, "second", %{"status" => 200, "marker" => "second", "capabilities" => ["apps"]})

    assert reconcile(pid) == result([change(@id, ~w(skills apps))])
    assert_bundle(ctx, "fixture-remote", "2.0.0", "second")
    assert reconcile(pid) == result([])
    assert_profile(ctx, pid)
  end

  defp start(ctx, opts \\ []) do
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
               "--auth",
               Keyword.get(opts, :auth, "chatgpt"),
               "--trust-env",
               Keyword.get(opts, :trust_env, "CODEX_CA_CERTIFICATE")
             ],
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
    on_exit(fn -> close_and_reap(ctx, pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_remote_plugin", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    proof = journal(ctx)["namespace"]
    assert proof["parent"] == File.read_link!("/proc/self/ns/net")
    assert proof["child"] != proof["parent"]
    assert proof["interfaces"] == ["lo"] and proof["default_route"] == false
    pid
  end

  defp close_and_reap(ctx, pid, connection) do
    StdioSessionFixture.close(pid, connection)
    if File.exists?(Path.join(ctx.root, "journal.json")), do: reap_native(ctx)
  end

  defp reap_native(ctx) do
    for event <- events(ctx, "native_started"),
        key <- ["pid", "controller_pid", "namespace_owner_pid"],
        do: await_process_exit(event[key])
  end

  defp await_process_exit(os_pid), do: await(fn -> not File.exists?("/proc/#{os_pid}") end)

  defp skill_body(contents),
    do: %{"plugin_id" => @remote, "name" => "inspect", "skill_md_contents" => contents}

  defp state(ctx), do: JSON.decode!(File.read!(Path.join(ctx.root, "remote-state.json")))

  defp write_state(ctx, data) do
    temporary = Path.join(ctx.root, "remote-state.pending")
    File.write!(temporary, JSON.encode!(data))
    File.rename!(temporary, Path.join(ctx.root, "remote-state.json"))
  end

  defp put_resource(ctx, resource, value),
    do: write_state(ctx, Map.put(state(ctx), resource, value))

  defp put_bundle(ctx, key, value),
    do: write_state(ctx, Map.update!(state(ctx), "bundles", &Map.put(&1, key, value)))

  defp snapshot(ctx, rows),
    do: put_resource(ctx, "installed", %{"status" => 200, "plugins" => rows})

  defp journal(ctx), do: JSON.decode!(File.read!(Path.join(ctx.root, "journal.json")))
  defp events(ctx, event), do: Enum.filter(journal(ctx)["events"], &(&1["event"] == event))

  defp plugin_base(ctx, name),
    do: Path.join(ctx.root, "codex/plugins/cache/openai-curated-remote/#{name}")

  defp version(ctx, name, version), do: Path.join(plugin_base(ctx, name), version)

  defp assert_bundle(ctx, name, version, marker) do
    assert File.read!(Path.join(version(ctx, name, version), "marker.txt")) == marker
    identity = Path.join(plugin_base(ctx, name), ".codex-remote-plugin-install.json")
    assert JSON.decode!(File.read!(identity))["remote_plugin_id"] == @remote
  end

  defp result(changed, failures \\ []),
    do: %{
      "changedPlugins" => changed,
      "failedRemotePluginIds" => failures,
      "failedMaterializationRemotePluginIds" => failures
    }

  defp change(id, capabilities),
    do: %{
      "id" => id,
      "hasMcps" => "mcps" in capabilities,
      "hasApps" => "apps" in capabilities,
      "hasHooks" => "hooks" in capabilities,
      "hasSkills" => "skills" in capabilities
    }

  defp reconcile(pid),
    do: call(pid, "plugin/reconcile", %{"reason" => "synthetic-source-profile"})

  defp call(pid, method, params) do
    case Session.request(pid, method, params) do
      {:ok, %{"result" => result}} ->
        result

      {:error, %Error{} = failure} ->
        flunk("Native #{method} #{failure.code}: #{inspect(failure.wire)}")
    end
  end

  defp error(pid, method, params) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             Session.request(pid, method, params)

    error
  end

  defp assert_profile(ctx, pid) do
    assert call(pid, "thread/loaded/list", %{})["data"] == []
    assert events(ctx, "forbidden_http") == []
    assert events(ctx, "fixture_error") == []
    assert length(events(ctx, "plugin_startup_disabled")) == length(events(ctx, "native_started"))
    assert length(events(ctx, "plugin_requests_enabled")) == length(events(ctx, "native_started"))

    for event <- events(ctx, "skill") ++ events(ctx, "installed") do
      assert event["bearer_verified"] and event["account_verified"]
    end

    for event <- events(ctx, "bundle") do
      assert event["tls_version"] in ["TLSv1.2", "TLSv1.3"]
      assert event["authorization_absent"] and event["account_absent"]
    end

    for event <- events(ctx, "installed") do
      assert event["query"]["includeDownloadUrls"] == ["true"]
      assert event["query"]["limit"] == ["200"]
    end
  end

  defp await(predicate, remaining \\ 500)

  defp await(predicate, remaining) when remaining > 0 do
    if predicate.() do
      :ok
    else
      Process.sleep(10)
      await(predicate, remaining - 1)
    end
  end

  defp await(_predicate, 0), do: flunk("owned remote-plugin process was not reaped")
end
