defmodule SamgitaCodexDriver.NativePluginShareProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_plugin_share_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @remote "plugins~Plugin_owned_share"
  @name "owned-share"
  @methods ~w(plugin/share/save plugin/share/list plugin/share/updateTargets plugin/share/checkout plugin/share/delete)

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip openssl), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-plugin-share-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    source = Path.join(root, "home/plugins/source-plugin")
    for dir <- ["home", "codex", "workspace", "tmp"], do: File.mkdir_p!(Path.join(root, dir))
    File.mkdir_p!(Path.join(source, ".codex-plugin"))
    File.write!(Path.join(source, ".codex-plugin/plugin.json"), JSON.encode!(%{"name" => @name}))
    File.write!(Path.join(source, "marker.txt"), "owned local λ🙂")
    on_exit(fn -> File.rm_rf!(root) end)
    ctx = %{root: root, source: source, binary: Path.expand(binary)}
    write_state(ctx, %{"seed" => true, "overrides" => %{}, "row" => %{}, "installed" => false})
    ctx
  end

  test "native save uploads only owned files and list preserves full share provenance", ctx do
    put_state(ctx, "seed", false)
    pid = start(ctx)
    targets = [target("user", "reader-1", "reader"), target("group", "editors-1", "editor")]

    result =
      call(
        pid,
        "plugin/share/save",
        Map.merge(save_params(ctx), %{"discoverability" => "PRIVATE", "shareTargets" => targets})
      )

    assert result == %{
             "remotePluginId" => @remote,
             "shareUrl" => "https://synthetic.invalid/share/owned",
             "canPublishToWorkspace" => true
           }

    assert mapping(ctx) == %{@remote => ctx.source}

    assert [%{"plugin" => plugin, "localPluginPath" => source}] =
             call(pid, "plugin/share/list", %{})["data"]

    assert source == ctx.source
    assert plugin["id"] == "owned-share@workspace-shared-with-me"
    assert plugin["remotePluginId"] == @remote and plugin["name"] == @name
    assert plugin["source"] == %{"type" => "remote"} and plugin["version"] == "1.0.0"
    assert plugin["installed"] == false and plugin["enabled"] == false
    assert plugin["installPolicy"] == "AVAILABLE" and plugin["authPolicy"] == "ON_USE"
    assert plugin["interface"]["displayName"] == "Owned share λ"
    context = plugin["shareContext"]
    assert context["remotePluginId"] == @remote and context["remoteVersion"] == "1.0.0"
    assert context["discoverability"] == "PRIVATE"
    assert context["shareUrl"] == result["shareUrl"]

    assert context["creatorAccountUserId"] == "owner-1" and
             context["creatorName"] == "Owned owner"

    assert context["canPublishToWorkspace"] == true
    assert context["sharePrincipals"] == principals(targets)
    assert length(events(ctx, "blob_upload")) == 1
    upload = List.last(events(ctx, "upload_url"))["body"]
    blob = List.last(events(ctx, "blob_upload"))

    assert upload["filename"] == "source-plugin.tar.gz" and
             upload["mime_type"] == "application/gzip"

    assert upload["size_bytes"] == blob["size"]
    refute Map.has_key?(upload, "plugin_id")

    assert blob["files"] == %{
             ".codex-plugin/plugin.json" => JSON.encode!(%{"name" => @name}),
             "marker.txt" => "owned local λ🙂"
           }

    assert List.last(events(ctx, "finalize"))["body"] == %{
             "file_id" => "file_owned",
             "etag" => "\"url_etag_owned\"",
             "discoverability" => "PRIVATE",
             "share_targets" => wire_targets(targets)
           }

    assert_profile(ctx, pid)
  end

  test "nullable metadata and empty principals remain explicit without inventing full values",
       ctx do
    put_state(ctx, "row", %{
      "share_url" => nil,
      "creator_account_user_id" => nil,
      "creator_name" => nil,
      "can_publish_to_workspace" => nil,
      "share_principals" => [],
      "release" => %{"version" => nil}
    })

    override(ctx, "finalize", %{
      "status" => 200,
      "body" => %{"plugin_id" => @remote, "share_url" => nil, "can_publish_to_workspace" => nil}
    })

    pid = start(ctx)

    assert call(pid, "plugin/share/save", save_params(ctx)) == %{
             "remotePluginId" => @remote,
             "shareUrl" => "",
             "canPublishToWorkspace" => nil
           }

    assert [%{"plugin" => plugin, "localPluginPath" => source}] =
             call(pid, "plugin/share/list", %{})["data"]

    assert source == ctx.source
    context = plugin["shareContext"]

    for field <-
          ~w(shareUrl creatorAccountUserId creatorName canPublishToWorkspace remoteVersion),
        do: assert(context[field] == nil)

    assert context["sharePrincipals"] == []
    assert plugin["version"] == nil and plugin["localVersion"] == nil
    assert_profile(ctx, pid)
  end

  test "target updates preserve all principal roles and inject workspace reader only for unlisted",
       ctx do
    put_state(ctx, "seed", false)
    pid = start(ctx)
    targets = [target("user", "reader-1", "reader"), target("group", "editors-1", "editor")]
    unlisted_targets = targets ++ [target("workspace", "isolated-auth-account", "reader")]

    assert call(
             pid,
             "plugin/share/save",
             Map.merge(save_params(ctx), %{
               "discoverability" => "UNLISTED",
               "shareTargets" => targets
             })
           )["remotePluginId"] == @remote

    assert List.last(events(ctx, "finalize"))["body"]["share_targets"] ==
             wire_targets(unlisted_targets)

    for discoverability <- ~w(PRIVATE UNLISTED LISTED) do
      expected =
        if discoverability == "UNLISTED",
          do: targets ++ [target("workspace", "isolated-auth-account", "reader")],
          else: targets

      assert call(pid, "plugin/share/updateTargets", %{
               "remotePluginId" => @remote,
               "discoverability" => discoverability,
               "shareTargets" => targets
             }) == %{"discoverability" => discoverability, "principals" => principals(expected)}

      assert List.last(events(ctx, "targets"))["body"] == %{
               "discoverability" => discoverability,
               "targets" => wire_targets(expected)
             }
    end

    assert call(pid, "plugin/share/updateTargets", %{
             "remotePluginId" => @remote,
             "discoverability" => "PRIVATE",
             "shareTargets" => []
           }) == %{"discoverability" => "PRIVATE", "principals" => principals([])}

    assert List.last(events(ctx, "targets"))["body"] == %{
             "discoverability" => "PRIVATE",
             "targets" => []
           }

    before_requests = length(backend_events(ctx))
    workspace = [target("workspace", "isolated-auth-account", "reader")]

    failure =
      error(pid, "plugin/share/updateTargets", %{
        "remotePluginId" => @remote,
        "discoverability" => "UNLISTED",
        "shareTargets" => workspace
      })

    assert failure["code"] == -32_600 and
             failure["message"] =~ "cannot include workspace principals"

    failure =
      error(
        pid,
        "plugin/share/save",
        Map.merge(save_params(ctx), %{"discoverability" => "PRIVATE", "shareTargets" => workspace})
      )

    assert failure["code"] == -32_600 and
             failure["message"] =~ "cannot include workspace principals"

    assert length(backend_events(ctx)) == before_requests
    assert_profile(ctx, pid)
  end

  test "local edits save as update and retained local mapping survives cold native restart",
       ctx do
    pid = start(ctx)
    call(pid, "plugin/share/save", save_params(ctx))
    File.write!(Path.join(ctx.source, "marker.txt"), "owned edited λ🙂")

    assert call(pid, "plugin/share/save", Map.put(save_params(ctx), "remotePluginId", @remote))[
             "remotePluginId"
           ] == @remote

    assert List.last(events(ctx, "upload_url"))["body"]["plugin_id"] == @remote
    assert List.last(events(ctx, "blob_upload"))["files"]["marker.txt"] == "owned edited λ🙂"
    body = List.last(events(ctx, "finalize"))["body"]
    assert body == %{"file_id" => "file_owned", "etag" => "\"url_etag_owned\""}

    assert List.last(events(ctx, "finalize"))["path"] ==
             "/backend-api/public/plugins/workspace/#{@remote}"

    assert_profile(ctx, pid)
    stop(ctx, pid)
    put_state(ctx, "installed", true)
    cold = start(ctx)

    assert [%{"localPluginPath" => source, "plugin" => plugin}] =
             call(cold, "plugin/share/list", %{})["data"]

    assert source == ctx.source and mapping(ctx) == %{@remote => ctx.source}
    assert plugin["version"] == "2.0.0" and plugin["localVersion"] == "2.0.0"
    assert plugin["installed"] == true and plugin["enabled"] == true
    assert File.read!(Path.join(source, "marker.txt")) == "owned edited λ🙂"
    assert length(events(ctx, "blob_upload")) == 2
    assert_profile(ctx, cold)
  end

  test "checkout writes personal marketplace and cold repeat preserves locally edited files",
       ctx do
    pid = start(ctx, trust_env: "SSL_CERT_FILE")
    result = call(pid, "plugin/share/checkout", %{"remotePluginId" => @remote})
    path = Path.join(ctx.root, "home/plugins/owned-share")
    marketplace = Path.join(ctx.root, "home/.agents/plugins/marketplace.json")

    assert result == %{
             "remotePluginId" => @remote,
             "pluginId" => "owned-share@codex-curated",
             "pluginName" => @name,
             "pluginPath" => path,
             "marketplaceName" => "codex-curated",
             "marketplacePath" => marketplace,
             "remoteVersion" => "1.0.0"
           }

    assert File.read!(Path.join(path, "marker.txt")) == "remote owned marker"
    assert JSON.decode!(File.read!(Path.join(path, ".codex-plugin/plugin.json")))["name"] == @name
    assert mapping(ctx) == %{@remote => path}

    assert JSON.decode!(File.read!(marketplace))["plugins"] == [
             %{
               "name" => @name,
               "source" => %{"source" => "local", "path" => "./plugins/owned-share"},
               "policy" => %{"installation" => "AVAILABLE", "authentication" => "ON_USE"}
             }
           ]

    File.write!(Path.join(path, "marker.txt"), "owned checkout edit")
    assert_profile(ctx, pid)
    stop(ctx, pid)
    cold = start(ctx)
    assert call(cold, "plugin/share/checkout", %{"remotePluginId" => @remote}) == result
    assert File.read!(Path.join(path, "marker.txt")) == "owned checkout edit"
    assert length(events(ctx, "bundle")) == 1
    assert [%{"localPluginPath" => ^path}] = call(cold, "plugin/share/list", %{})["data"]
    assert length(JSON.decode!(File.read!(marketplace))["plugins"]) == 1
    assert_profile(ctx, cold)
  end

  test "deletion removes share mapping while preserving local source and cold list absence",
       ctx do
    pid = start(ctx)
    call(pid, "plugin/share/save", save_params(ctx))
    assert call(pid, "plugin/share/delete", %{"remotePluginId" => @remote}) == %{}
    assert mapping(ctx) == %{}
    assert File.read!(Path.join(ctx.source, "marker.txt")) == "owned local λ🙂"
    assert call(pid, "plugin/share/list", %{}) == %{"data" => []}
    assert List.last(events(ctx, "delete"))["status"] == 204
    assert_profile(ctx, pid)
    stop(ctx, pid)
    cold = start(ctx)
    assert call(cold, "plugin/share/list", %{}) == %{"data" => []}
    assert mapping(ctx) == %{} and File.dir?(ctx.source)
    assert_profile(ctx, cold)
  end

  test "HTTP decode missing metadata upload and input identity failures remain explicit", ctx do
    pid = start(ctx)

    for {status, code} <- [{401, -32_603}, {404, -32_600}, {429, -32_603}, {503, -32_603}] do
      override(ctx, "created", %{"status" => status})
      failure = error(pid, "plugin/share/list", %{})
      assert failure["code"] == code and failure["message"] =~ "failed with status #{status}"
    end

    override(ctx, "created", %{"status" => 200, "raw" => "synthetic invalid JSON"})

    assert error(pid, "plugin/share/list", %{})["message"] =~
             "failed to parse remote plugin catalog response"

    clear_overrides(ctx)

    for {row, fragment} <- [
          {%{"share_principals" => nil}, "did not include share_principals"},
          {%{"discoverability" => nil}, "did not include discoverability"},
          {%{"name" => "invalid plugin name"}, "invalid remote plugin config id"}
        ] do
      put_state(ctx, "row", row)
      failure = error(pid, "plugin/share/list", %{})
      assert failure["code"] == -32_603 and failure["message"] =~ fragment
    end

    put_state(ctx, "row", %{})
    override(ctx, "upload_url", %{"status" => 200, "merge" => %{"etag" => nil}})
    before_uploads = length(events(ctx, "blob_upload"))
    assert error(pid, "plugin/share/save", save_params(ctx))["message"] =~ "etag"
    assert length(events(ctx, "blob_upload")) == before_uploads
    clear_overrides(ctx)
    override(ctx, "blob_upload", %{"status" => 503})

    assert error(pid, "plugin/share/save", save_params(ctx))["message"] =~
             "failed with status 503"

    clear_overrides(ctx)

    override(ctx, "finalize", %{
      "status" => 200,
      "body" => %{"plugin_id" => "", "share_url" => nil}
    })

    assert error(pid, "plugin/share/save", save_params(ctx))["message"] =~
             "did not include a plugin id"

    clear_overrides(ctx)
    before_requests = length(backend_events(ctx))

    for method <-
          ~w(plugin/share/save plugin/share/updateTargets plugin/share/checkout plugin/share/delete) do
      params = Map.put(params(ctx, method), "remotePluginId", "invalid/id")
      failure = error(pid, method, params)
      assert failure["code"] == -32_600 and failure["message"] =~ "invalid remote plugin id"
    end

    assert error(pid, "plugin/share/save", Map.put(save_params(ctx), "discoverability", "LISTED"))[
             "message"
           ] =~ "LISTED is not supported"

    assert error(
             pid,
             "plugin/share/save",
             Map.merge(save_params(ctx), %{
               "remotePluginId" => @remote,
               "discoverability" => "PRIVATE"
             })
           )["message"] =~ "only supported when creating"

    assert length(backend_events(ctx)) == before_requests
    assert_profile(ctx, pid)
  end

  test "plugins sharing and authentication gates are distinct and prevent backend calls", ctx do
    disabled = start(ctx, plugins: "disabled")

    for method <- @methods,
        do:
          assert(
            error(disabled, method, params(ctx, method))["message"] =~
              "plugin sharing is not enabled"
          )

    assert backend_events(ctx) == []
    assert_profile(ctx, disabled)
    stop(ctx, disabled)
    sharing_off = start(ctx, sharing: "disabled")

    for method <- ~w(plugin/share/save plugin/share/updateTargets plugin/share/checkout),
        do:
          assert(
            error(sharing_off, method, params(ctx, method))["message"] =~
              "plugin sharing is disabled"
          )

    assert backend_events(ctx) == []
    assert [_] = call(sharing_off, "plugin/share/list", %{})["data"]
    assert call(sharing_off, "plugin/share/delete", %{"remotePluginId" => @remote}) == %{}
    assert_profile(ctx, sharing_off)
    stop(ctx, sharing_off)

    for auth <- ~w(none apikey) do
      pid = start(ctx, auth: auth)
      before_requests = length(backend_events(ctx))

      for method <- @methods do
        failure = error(pid, method, params(ctx, method))

        assert failure["code"] == -32_600 and
                 failure["message"] =~ "chatgpt authentication required"
      end

      assert length(backend_events(ctx)) == before_requests
      assert_profile(ctx, pid)
      stop(ctx, pid)
    end
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
               Keyword.get(opts, :trust_env, "CODEX_CA_CERTIFICATE"),
               "--plugins",
               Keyword.get(opts, :plugins, "enabled"),
               "--sharing",
               Keyword.get(opts, :sharing, "enabled")
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
             Session.initialize(pid, %{"name" => "samgita_plugin_share", "version" => "0.1.0"}, %{
               "experimentalApi" => true
             })

    proof = journal(ctx)["namespace"]

    assert proof["parent"] == File.read_link!("/proc/self/ns/net") and
             proof["child"] != proof["parent"]

    assert proof["interfaces"] == ["lo"] and proof["default_route"] == false
    pid
  end

  defp close_and_reap(ctx, pid, connection) do
    StdioSessionFixture.close(pid, connection)
    reap(ctx)
  end

  defp stop(ctx, pid) do
    assert :ok = Session.close(pid)
    reap(ctx)
  end

  defp reap(ctx) do
    for event <- events(ctx, "native_started"),
        key <- ~w(pid controller_pid namespace_owner_pid),
        do: await(fn -> not File.exists?("/proc/#{event[key]}") end)
  end

  defp save_params(ctx), do: %{"pluginPath" => ctx.source}
  defp params(ctx, "plugin/share/save"), do: save_params(ctx)
  defp params(_ctx, "plugin/share/list"), do: %{}

  defp params(_ctx, "plugin/share/updateTargets"),
    do: %{"remotePluginId" => @remote, "discoverability" => "PRIVATE", "shareTargets" => []}

  defp params(_ctx, _method), do: %{"remotePluginId" => @remote}
  defp target(type, id, role), do: %{"principalType" => type, "principalId" => id, "role" => role}

  defp wire_targets(targets),
    do:
      Enum.map(
        targets,
        &%{
          "principal_type" => &1["principalType"],
          "principal_id" => &1["principalId"],
          "role" => &1["role"]
        }
      )

  defp principals(targets),
    do: [
      %{
        "principalType" => "user",
        "principalId" => "owner-1",
        "role" => "owner",
        "name" => "Owned owner"
      }
      | Enum.map(targets, &Map.put(&1, "name", "Owned " <> &1["principalId"]))
    ]

  defp state(ctx), do: JSON.decode!(File.read!(Path.join(ctx.root, "share-state.json")))

  defp write_state(ctx, data) do
    path = Path.join(ctx.root, "share-state.json")
    File.write!(path <> ".pending", JSON.encode!(data))
    File.rename!(path <> ".pending", path)
  end

  defp put_state(ctx, key, value), do: write_state(ctx, Map.put(state(ctx), key, value))

  defp override(ctx, key, value),
    do: put_state(ctx, "overrides", Map.put(state(ctx)["overrides"], key, value))

  defp clear_overrides(ctx), do: put_state(ctx, "overrides", %{})
  defp journal(ctx), do: JSON.decode!(File.read!(Path.join(ctx.root, "journal.json")))
  defp events(ctx, event), do: Enum.filter(journal(ctx)["events"], &(&1["event"] == event))

  defp backend_events(ctx),
    do:
      Enum.filter(
        journal(ctx)["events"],
        &(&1["event"] in ~w(upload_url finalize created installed detail targets delete))
      )

  defp mapping(ctx) do
    path = Path.join(ctx.root, "codex/.tmp/plugin-share-local-paths-v1.json")

    if File.exists?(path),
      do: JSON.decode!(File.read!(path))["localPluginPathsByRemotePluginId"],
      else: %{}
  end

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
    assert events(ctx, "forbidden_http") == [] and events(ctx, "fixture_error") == []
    assert length(events(ctx, "plugin_startup_disabled")) == length(events(ctx, "native_started"))

    assert length(events(ctx, "share_requests_configured")) ==
             length(events(ctx, "native_started"))

    for event <- backend_events(ctx),
        do: assert(event["bearer_verified"] and event["account_verified"])

    assert_object_transfers(ctx)
    for event <- events(ctx, "created"), do: assert(event["query"]["limit"] == ["200"])

    for event <- events(ctx, "detail"),
        do: assert(event["query"]["includeDownloadUrls"] == ["true"])
  end

  defp assert_object_transfers(ctx) do
    for event <- events(ctx, "blob_upload") ++ events(ctx, "bundle") do
      assert event["tls_version"] in ["TLSv1.2", "TLSv1.3"]
      assert event["authorization_absent"] and event["account_absent"]
    end

    for event <- events(ctx, "blob_upload"),
        do: assert(event["mime_type"] == "application/gzip" and event["blob_type"] == "BlockBlob")
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

  defp await(_predicate, 0), do: flunk("owned plugin-share process was not reaped")
end
