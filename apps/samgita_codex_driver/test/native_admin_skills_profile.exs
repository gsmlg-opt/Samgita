defmodule SamgitaCodexDriver.NativeAdminSkillsProfileTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_admin_skills_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @skill_sha "bb2b50bc56418c06bd450b1ef6d6ae48d202951f5a243a132cbe0a31ae0f1501"
  @system_config "[skills.bundled]\nenabled = false\n"
  @skill_path "/etc/codex/skills/owned-admin-discovery/SKILL.md"

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert sha(File.read!(binary)) == @binary_sha
    for tool <- ~w(python3 unshare ip mount setpriv), do: assert(System.find_executable(tool))
    original_environment = {System.get_env("HOME"), System.get_env("CODEX_HOME")}
    parent_etc = parent_etc()

    root =
      "/tmp/samgita-admin-skills-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"

    File.mkdir!(root)
    for directory <- ~w(home codex workspace tmp), do: File.mkdir!(Path.join(root, directory))

    on_exit(fn ->
      assert {System.get_env("HOME"), System.get_env("CODEX_HOME")} == original_environment
      assert parent_etc() == parent_etc
    end)

    {:ok, owner} =
      Stdio.open(
        executable: System.find_executable("python3"),
        args: ["-I", @script, "--root", root, "--codex", Path.expand(binary)],
        cwd: Path.join(root, "workspace"),
        inherit_env: [],
        env: %{
          "HOME" => Path.join(root, "home"),
          "CODEX_HOME" => Path.join(root, "codex"),
          "TMPDIR" => Path.join(root, "tmp"),
          "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
          "RUST_LOG" => "off",
          "NO_COLOR" => "1",
          "PYTHONDONTWRITEBYTECODE" => "1"
        }
      )

    ctx = %{root: root, owner: owner}
    on_exit(fn -> cleanup(ctx) end)
    await(fn -> startup_ready?(ctx) end)
    proof = json(ctx, "state.json")

    for name <- ~w(user mnt net) do
      assert proof["parent_namespaces"][name] == File.read_link!("/proc/self/ns/#{name}")
      refute proof["namespaces"][name] == proof["parent_namespaces"][name]
    end

    assert proof["interfaces"] == ["lo"]
    assert proof["default_route"] == false and proof["ipv6_default_route"] == false
    assert proof["binary_sha256"] == @binary_sha
    assert_privileges(proof["privileges"])
    assert proof["mounted"]["recursive_private"] == true
    assert proof["mounted"]["mount"]["target"] == "/etc"

    assert MapSet.subset?(
             MapSet.new(~w(ro nodev nosuid noexec)),
             MapSet.new(proof["mounted"]["mount"]["flags"])
           )

    assert proof["mounted"]["mount"]["propagation"] == []

    assert get_in(proof, ["mounted", "files", "codex/config.toml", "sha256"]) ==
             sha(@system_config)

    assert get_in(proof, [
             "mounted",
             "files",
             "codex/skills/owned-admin-discovery/SKILL.md",
             "sha256"
           ]) == @skill_sha

    assert [ready] = events(ctx, "fixture_ready")
    assert ready["cache_preseeded"] == false
    assert ready["inherited_host_credentials"] == false and ready["model_responses_served"] == 0
    config = File.read!(Path.join(root, "codex/config.toml"))
    assert config =~ "model_catalog_json = "
    assert config =~ "requires_openai_auth = false"
    assert config =~ "plugins = false" and config =~ "recommended_plugins = false"
    refute config =~ "skills.bundled"
    ctx |> Map.put(:config, config) |> Map.put(:proof, proof)
  end

  test "stock Admin root preserves exact metadata across reload and owned cold restart", ctx do
    initial = connect(ctx, "initial")
    assert_admin(ctx, listed(ctx, initial))
    assert_safe(ctx, initial)
    control(ctx, "snapshotInitial")
    before = json(ctx, "snapshot-initial.json")

    assert_admin(ctx, listed(ctx, initial))
    assert_safe(ctx, initial)
    control(ctx, "snapshotReloaded")
    assert json(ctx, "snapshot-reloaded.json") == before
    first_pid = json(ctx, "state.json")["native_pids"]["initial"]
    assert :ok = Session.close(initial)

    control(ctx, "restart")
    pids = json(ctx, "state.json")["native_pids"]
    assert pids["initial"] == first_pid and pids["restarted"] != first_pid
    refute File.exists?("/proc/#{first_pid}")
    restarted = connect(ctx, "restarted")
    assert_admin(ctx, listed(ctx, restarted))
    assert_safe(ctx, restarted)
    control(ctx, "snapshotRestarted")
    assert json(ctx, "snapshot-restarted.json") == before

    assert Enum.map(events(ctx, "discovery_snapshot"), & &1["name"]) == [
             "initial",
             "reloaded",
             "restarted"
           ]

    assert Enum.map(events(ctx, "native_started"), & &1["name"]) == ["initial", "restarted"]

    for row <- events(ctx, "native_started") do
      assert row["bundled_override"] == false
      assert [_binary, "app-server", "--listen", _socket] = row["arguments"]
    end

    for row <- events(ctx, "native_ready") do
      assert row["namespaces"] == ctx.proof["namespaces"]
      assert_privileges(row["privileges"])
    end

    assert :ok = Session.close(restarted)
    control(ctx, "close")
    assert length(events(ctx, "native_stopped")) == 2
    assert length(events(ctx, "fixture_closed")) == 1
    assert events(ctx, "forbidden_http") == []
    assert events(ctx, "fixture_error") == []
    for pid <- Map.values(pids), do: refute(File.exists?("/proc/#{pid}"))
  end

  defp connect(ctx, name) do
    {:ok, pid} =
      Session.start_link(
        transport: {UnixSocket, [socket_path: Path.join(ctx.root, "native-#{name}.sock")]},
        request_timeout_ms: 10_000
      )

    on_exit(fn -> if Process.alive?(pid), do: assert(:ok = Session.close(pid)) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_admin_skills", "version" => "0.1.0"},
               %{"experimentalApi" => false}
             )

    pid
  end

  defp listed(ctx, pid) do
    cwd = Path.join(ctx.root, "workspace")

    assert %{"data" => [%{"cwd" => ^cwd, "errors" => [], "skills" => skills}]} =
             call(pid, "skills/list", %{"cwds" => [cwd], "forceReload" => true})

    skills
  end

  defp assert_admin(ctx, skills) do
    assert skills == [
             %{
               "name" => "owned-admin-discovery",
               "description" => "Owned synthetic admin discovery metadata.",
               "path" => @skill_path,
               "scope" => "admin",
               "enabled" => true,
               "pluginId" => nil
             }
           ]

    # Parent reads the owned source alias; /etc in this process remains host /etc.
    path = Path.join(ctx.root, "etc/codex/skills/owned-admin-discovery/SKILL.md")
    assert File.lstat!(path).type == :regular
    assert byte_size(File.read!(path)) == 154
    assert sha(File.read!(path)) == @skill_sha
    assert File.read!(Path.join(ctx.root, "etc/codex/config.toml")) == @system_config

    assert get_in(ctx.proof, [
             "mounted",
             "files",
             "codex/skills/owned-admin-discovery/SKILL.md",
             "inode"
           ]) == File.stat!(path).inode
  end

  defp assert_safe(ctx, pid) do
    assert call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    assert {:ok, rows} = Session.drain(pid)
    refute Enum.any?(rows, &(&1.kind == :server_request))

    refute Enum.any?(rows, fn row ->
             method = row.wire["method"] || ""
             String.starts_with?(method, ["thread/", "turn/", "item/"])
           end)

    assert events(ctx, "forbidden_http") == []
    assert File.read!(Path.join(ctx.root, "codex/config.toml")) == ctx.config
    refute File.exists?(Path.join(ctx.root, "codex/auth.json"))
    refute File.exists?(Path.join(ctx.root, "codex/skills/.system"))
  end

  defp assert_privileges(proof) do
    assert Map.keys(proof) |> Enum.sort() == ~w(CapAmb CapBnd CapEff CapInh CapPrm NoNewPrivs)
    assert proof["NoNewPrivs"] == "1"

    for key <- ~w(CapAmb CapBnd CapEff CapInh CapPrm),
        do: assert(String.to_integer(proof[key], 16) == 0)
  end

  defp parent_etc do
    info = File.stat!("/etc")

    mounts =
      "/proc/self/mountinfo"
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.filter(fn line -> Enum.at(String.split(line), 4) in ["/", "/etc"] end)

    %{
      namespace: File.read_link!("/proc/self/ns/mnt"),
      device: info.major_device,
      minor_device: info.minor_device,
      inode: info.inode,
      mounts: mounts
    }
  end

  defp control(ctx, op) do
    id = "owned-admin-skills-#{System.unique_integer([:positive])}"
    assert {:ok, _} = Stdio.send(ctx.owner, JSON.encode!(%{"id" => id, "op" => op}))
    await(fn -> Enum.find(events(ctx, "control_done"), &(&1["id"] == id)) end)
  end

  defp cleanup(ctx) do
    assert :ok = Stdio.close(ctx.owner)

    if File.exists?(Path.join(ctx.root, "state.json")) do
      proof = json(ctx, "state.json")

      for pid <-
            Map.values(proof["native_pids"]) ++
              [proof["controller_pid"], proof["namespace_owner_pid"]],
          do: assert_process_reaped(pid)

      assert events(ctx, "fixture_closed") != []
    end

    IO.puts(:stderr, "Owned Admin-skill evidence retained: #{ctx.root}")
  end

  defp startup_ready?(ctx) do
    if File.exists?(Path.join(ctx.root, "startup-failure.json")),
      do: flunk("Owned Admin startup failed: #{inspect(json(ctx, "startup-failure.json"))}")

    File.exists?(Path.join(ctx.root, "native-initial.sock"))
  end

  defp assert_process_reaped(pid), do: await(fn -> not File.exists?("/proc/#{pid}") end)

  defp await(predicate, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 10_000

    case predicate.() do
      value when value not in [false, nil] ->
        value

      _ ->
        assert System.monotonic_time(:millisecond) < deadline, "Owned Admin-skill deadline"

        receive do
        after
          10 -> :ok
        end

        await(predicate, deadline)
    end
  end

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp sha(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  defp json(ctx, name), do: ctx.root |> Path.join(name) |> File.read!() |> JSON.decode!()
  defp events(ctx, kind), do: Enum.filter(json(ctx, "journal.json"), &(&1["event"] == kind))
end
