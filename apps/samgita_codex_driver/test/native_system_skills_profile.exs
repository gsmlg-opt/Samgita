defmodule SamgitaCodexDriver.NativeSystemSkillsProfileTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_system_skills_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  # Immutable rust-v0.163.0 skills/src/assets/samples/review-agent/SKILL.md.
  @skill_sha "07079efd0dc76f05fade424e5dfb048dce1de2df7626e1a4f56292a4f3f92228"
  @description "Perform a read-only, defect-first review of a specified code change and return every actionable finding. Use when another agent delegates review of uncommitted changes, a base-branch diff, a commit, or custom review instructions."

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert sha(File.read!(binary)) == @binary_sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))
    original_environment = {System.get_env("HOME"), System.get_env("CODEX_HOME")}

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-system-skills-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    File.mkdir!(root)
    for directory <- ~w(home codex workspace tmp), do: File.mkdir!(Path.join(root, directory))

    on_exit(fn ->
      assert {System.get_env("HOME"), System.get_env("CODEX_HOME")} == original_environment
    end)

    {:ok, owner} =
      Stdio.open(
        executable: System.find_executable("python3"),
        args: [@script, "--root", root, "--codex", Path.expand(binary)],
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
    await(fn -> File.exists?(Path.join(root, "native-enabled.sock")) end)
    proof = json(ctx, "state.json")
    assert proof["parent_namespace"] == File.read_link!("/proc/self/ns/net")
    assert proof["namespace"] != proof["parent_namespace"]
    assert proof["interfaces"] == ["lo"]
    assert proof["default_route"] == false and proof["ipv6_default_route"] == false
    assert [ready] = events(ctx, "fixture_ready")
    assert ready["cache_preseeded"] == false
    assert ready["inherited_host_credentials"] == false and ready["model_responses_served"] == 0
    config = File.read!(Path.join(root, "codex/config.toml"))
    assert config =~ "model_catalog_json = "
    assert config =~ "requires_openai_auth = false"
    assert config =~ "plugins = false" and config =~ "recommended_plugins = false"
    refute config =~ "skills.bundled"
    refute File.exists?(Path.join(root, "codex/auth.json"))
    Map.put(ctx, :config, config)
  end

  test "native disabled bundles hide System skills while preserving another process cache", ctx do
    enabled = connect(ctx, "enabled")
    before = system_skills(ctx, listed(ctx, enabled))
    refute before == []
    assert_review(ctx, before)
    control(ctx, "snapshotEnabled")
    cache = json(ctx, "cache-enabled.json")
    assert_cache(ctx, cache)
    enabled_pid = json(ctx, "state.json")["native_pids"]["enabled"]

    # The second process changes only its explicit CLI override. A remains live.
    control(ctx, "startDisabled")
    disabled = connect(ctx, "disabled")
    pids = json(ctx, "state.json")["native_pids"]
    assert pids["enabled"] == enabled_pid and pids["disabled"] != enabled_pid
    assert File.exists?("/proc/#{enabled_pid}")
    assert system_skills(ctx, listed(ctx, disabled)) == []
    control(ctx, "snapshotDisabled")
    assert json(ctx, "cache-disabled.json") == cache
    assert_cache(ctx, cache)
    assert_safe(ctx, disabled)

    # forceReload on the still-enabled process must retain the same System rows.
    after_reload = system_skills(ctx, listed(ctx, enabled))
    assert after_reload == before
    assert_review(ctx, after_reload)
    control(ctx, "snapshotReloaded")
    assert json(ctx, "cache-reloaded.json") == cache
    assert_cache(ctx, cache)
    assert_safe(ctx, enabled)

    assert Enum.map(events(ctx, "native_started"), & &1["bundled_override"]) == [
             "skills.bundled.enabled=true",
             "skills.bundled.enabled=false"
           ]

    assert Enum.map(events(ctx, "cache_snapshot"), & &1["name"]) == [
             "enabled",
             "disabled",
             "reloaded"
           ]

    assert :ok = Session.close(disabled)
    assert :ok = Session.close(enabled)
    control(ctx, "close")
    assert length(events(ctx, "native_stopped")) == 2
    assert length(events(ctx, "fixture_closed")) == 1
    assert events(ctx, "forbidden_http") == []
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
               %{"name" => "samgita_system_skills", "version" => "0.1.0"},
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

  defp system_skills(ctx, skills) do
    cache = Path.join(ctx.root, "codex/skills/.system")

    skills
    |> Enum.filter(&(&1["scope"] == "system"))
    |> Enum.map(fn skill ->
      path = skill["path"]
      assert is_binary(path) and String.starts_with?(path, cache <> "/")
      assert Path.expand(path) == path
      assert File.lstat!(path).type == :regular
      skill
    end)
    |> Enum.sort_by(& &1["path"])
  end

  defp assert_review(ctx, skills) do
    assert [review] = Enum.filter(skills, &(&1["name"] == "review-agent"))
    assert review["scope"] == "system" and review["enabled"] == true
    assert review["description"] == @description
    assert Map.fetch!(review, "pluginId") == nil
    path = Path.join(ctx.root, "codex/skills/.system/review-agent/SKILL.md")
    assert review["path"] == path
    assert sha(File.read!(path)) == @skill_sha
  end

  defp assert_cache(ctx, snapshot) do
    assert get_in(snapshot, ["review-agent/SKILL.md", "sha256"]) == @skill_sha
    assert Map.has_key?(snapshot, ".codex-system-skills.marker")

    for {relative, metadata} <- snapshot do
      path = Path.join(ctx.root, "codex/skills/.system/" <> relative)
      assert File.lstat!(path).type == :regular
      bytes = File.read!(path)
      assert byte_size(bytes) == metadata["bytes"] and sha(bytes) == metadata["sha256"]
    end
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
  end

  defp control(ctx, op) do
    id = "owned-system-skills-#{System.unique_integer([:positive])}"
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

    IO.puts(:stderr, "Owned system-skill evidence retained: #{ctx.root}")
  end

  defp assert_process_reaped(pid), do: await(fn -> not File.exists?("/proc/#{pid}") end)

  defp await(predicate, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 10_000

    case predicate.() do
      value when value not in [false, nil] ->
        value

      _ ->
        assert System.monotonic_time(:millisecond) < deadline, "Owned system-skill deadline"

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
