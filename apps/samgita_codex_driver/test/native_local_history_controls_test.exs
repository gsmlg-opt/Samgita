defmodule SamgitaCodexDriver.NativeLocalHistoryControlsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}

  import TurnFixture,
    only: [call: 3, start: 1, start: 2, thread: 3, upstream_error: 3, upstream_error: 4]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @missing "00000000-0000-4000-8000-000000000000"

  setup tags do
    ctx = TurnFixture.setup(tags)
    config = Path.join(ctx.fixture.codex_home, "config.toml")
    prefix = "features.local_thread_store_compression = false\n"

    prefix =
      if tags[:in_memory] do
        store = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
        ~s(experimental_thread_store = { type = "in_memory", id = "#{store}" }\n) <> prefix
      else
        prefix
      end

    File.write!(config, prefix <> File.read!(config))
    ctx
  end

  test "loaded legacy memory-mode updates persist both native JSONL and SQLite", ctx do
    pid = start(ctx)
    id = thread(ctx, pid, %{"historyMode" => "legacy"})

    for mode <- ["disabled", "enabled", "disabled"] do
      assert set_mode(pid, id, mode) == %{}
      path = call(pid, "thread/read", %{"threadId" => id})["thread"]["path"]
      assert_owned(ctx, path)
      assert File.regular?(path)
      assert latest_meta(path, id)["memory_mode"] == mode
      assert stored_mode(ctx, id) == mode
    end

    assert call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"][
             "turns"
           ] == []

    assert_idle(ctx, pid)
  end

  test "paginated memory mode survives native restart and cold metadata updates without loading",
       ctx do
    pid = start(ctx)
    id = named(ctx, pid, "paginated")
    assert set_mode(pid, id, "disabled") == %{}
    assert stored_mode(ctx, id) == "disabled"
    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert loaded(cold) == []
    assert stored_mode(ctx, id) == "disabled"
    assert set_mode(cold, id, "enabled") == %{}
    assert stored_mode(ctx, id) == "enabled"
    assert loaded(cold) == []
    assert :ok = Session.close(cold)
    again = start(ctx)
    assert stored_mode(ctx, id) == "enabled"
    assert loaded(again) == []
    assert set_mode(again, id, "disabled") == %{}
    assert stored_mode(ctx, id) == "disabled"
    assert loaded(again) == []

    assert call(again, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"][
             "turns"
           ] == []

    assert_idle(ctx, again)
  end

  test "memory mode rejects unknown ephemeral malformed and unnegotiated changes", ctx do
    pid = start(ctx)
    id = named(ctx, pid, "legacy")
    assert set_mode(pid, id, "disabled") == %{}

    assert upstream_error(pid, "thread/memoryMode/set", %{
             "threadId" => @missing,
             "mode" => "enabled"
           }) ==
             invalid("no rollout found for thread id #{@missing}")

    ephemeral = thread(ctx, pid, %{"ephemeral" => true})

    assert upstream_error(pid, "thread/memoryMode/set", %{
             "threadId" => ephemeral,
             "mode" => "disabled"
           }) ==
             invalid("ephemeral thread does not support metadata updates: #{ephemeral}")

    for params <- [
          %{"threadId" => id, "mode" => "polluted"},
          %{"threadId" => id, "mode" => nil},
          %{"threadId" => id},
          %{"threadId" => 17, "mode" => "enabled"}
        ] do
      assert_invalid_wire(pid, "thread/memoryMode/set", params)
      assert stored_mode(ctx, id) == "disabled"
    end

    error =
      upstream_error(pid, "thread/memoryMode/set", %{
        "threadId" => "not-an-id",
        "mode" => "enabled"
      })

    assert error["code"] == -32_600
    assert String.starts_with?(error["message"], "invalid thread id: ")
    assert_idle(ctx, pid)
    assert :ok = Session.close(pid)
    stable = start(ctx, experimental: false)

    assert upstream_error(
             stable,
             "thread/memoryMode/set",
             %{"threadId" => id, "mode" => "enabled"},
             validation: :wire
           ) ==
             invalid("thread/memoryMode/set requires experimentalApi capability")

    assert stored_mode(ctx, id) == "disabled"
    assert loaded(stable) == []
    assert_idle(ctx, stable)
  end

  test "compression trigger produces cold Zstandard storage and native reads preserve old bytes",
       ctx do
    pid = start(ctx)
    old_id = named(ctx, pid, "legacy")
    recent_id = named(ctx, pid, "legacy")
    old_path = call(pid, "thread/read", %{"threadId" => old_id})["thread"]["path"]
    recent_path = call(pid, "thread/read", %{"threadId" => recent_id})["thread"]["path"]
    assert_owned(ctx, old_path)
    assert_owned(ctx, recent_path)
    original = File.read!(old_path)
    recent = File.read!(recent_path)
    assert :ok = Session.close(pid)

    # Only this native-created, now-closed fixture is aged. The pinned worker
    # requires at least seven days; no native lock or cooldown is bypassed.
    aged_at = System.os_time(:second) - 8 * 24 * 60 * 60
    assert :ok = File.touch(old_path, aged_at)
    cold = start(ctx)
    before_id = summary(cold, %{"conversationId" => old_id})
    before_path = summary(cold, %{"rolloutPath" => old_path})

    # Empty legacy ID reads retain SQLite metadata; path reads use file mtime.
    assert before_path["updatedAt"] ==
             aged_at
             |> Kernel.*(1000)
             |> DateTime.from_unix!(:millisecond)
             |> DateTime.to_iso8601()

    assert Map.put(before_path, "updatedAt", before_id["updatedAt"]) == before_id
    assert loaded(cold) == []
    compressed = old_path <> ".zst"
    refute File.exists?(compressed)
    assert call(cold, "rollout/compress", nil) == %{}
    await(fn -> not File.exists?(old_path) and File.regular?(compressed) end)
    assert <<0x28, 0xB5, 0x2F, 0xFD, _rest::binary>> = File.read!(compressed)
    assert File.read!(recent_path) == recent
    refute File.exists?(recent_path <> ".zst")
    assert summary(cold, %{"conversationId" => old_id}) == before_id
    assert summary(cold, %{"rolloutPath" => old_path}) == before_path
    assert loaded(cold) == []

    # A second ACK is only another trigger, potentially skipped by cooldown.
    assert call(cold, "rollout/compress", nil) == %{}
    assert File.regular?(compressed)
    assert :ok = Session.close(cold)
    restarted = start(ctx)
    assert summary(restarted, %{"conversationId" => old_id}) == before_id
    assert summary(restarted, %{"rolloutPath" => old_path}) == before_path
    resumed = call(restarted, "thread/resume", %{"threadId" => old_id})["thread"]
    assert resumed["id"] == old_id
    assert resumed["turns"] == []
    assert File.regular?(old_path)
    assert String.starts_with?(File.read!(old_path), original)
    assert_idle(ctx, restarted)
  end

  @tag in_memory: true
  test "nonlocal compression and path summaries reject explicitly and negotiation still applies",
       ctx do
    pid = start(ctx)

    unsupported = %{"code" => -32_601, "message" => "rollout/compress is not supported yet"}
    assert upstream_error(pid, "rollout/compress", nil) == unsupported

    # The pinned internally tagged serde unit accepts an empty map, although
    # the exported JSON Schema restricts this method's params to null/omitted.
    assert upstream_error(pid, "rollout/compress", %{}, validation: :wire) == unsupported

    assert upstream_error(pid, "getConversationSummary", %{
             "rolloutPath" => Path.join(ctx.fixture.codex_home, "absent.jsonl")
           }) ==
             invalid("rollout path queries are only supported with the local thread store")

    for params <- [%{"unexpected" => true}, 17] do
      assert_invalid_wire(pid, "rollout/compress", params)
    end

    assert_idle(ctx, pid)
    assert :ok = Session.close(pid)
    stable = start(ctx, experimental: false)

    assert upstream_error(stable, "rollout/compress", nil, validation: :wire) ==
             invalid("rollout/compress requires experimentalApi capability")

    assert loaded(stable) == []
    assert_idle(ctx, stable)
  end

  test "empty persisted summaries support ID absolute relative paths and native cold restart",
       ctx do
    pid = start(ctx)
    id = named(ctx, pid, "paginated")
    native = call(pid, "thread/read", %{"threadId" => id})["thread"]
    path = native["path"]
    assert_owned(ctx, path)
    by_id = summary(pid, %{"conversationId" => id})

    assert Map.take(
             by_id,
             ~w(conversationId path preview modelProvider cwd cliVersion source gitInfo)
           ) == %{
             "conversationId" => id,
             "path" => path,
             "preview" => "",
             "modelProvider" => "fixture",
             "cwd" => ctx.fixture.workspace,
             "cliVersion" => native["cliVersion"],
             "source" => native["source"],
             "gitInfo" => nil
           }

    for {key, native_key} <- [{"timestamp", "createdAt"}, {"updatedAt", "updatedAt"}] do
      assert by_id[key] =~ ~r/\.\d{3}Z\z/
      assert {:ok, timestamp, 0} = DateTime.from_iso8601(by_id[key])
      assert DateTime.to_unix(timestamp) == native[native_key]
    end

    assert summary(pid, %{"rolloutPath" => path}) == by_id
    relative = Path.relative_to(path, ctx.fixture.codex_home)
    refute Path.type(relative) == :absolute
    assert summary(pid, %{"rolloutPath" => relative}) == by_id
    assert :ok = Session.close(pid)
    cold = start(ctx, experimental: false)
    assert loaded(cold) == []
    assert summary(cold, %{"conversationId" => id}) == by_id
    assert summary(cold, %{"rolloutPath" => relative}) == by_id
    assert loaded(cold) == []
    assert_idle(ctx, cold)
  end

  test "summary missing paths IDs and invalid selectors fail without fabricating results", ctx do
    pid = start(ctx)

    assert upstream_error(pid, "getConversationSummary", %{"conversationId" => @missing}) ==
             invalid("no rollout found for conversation id #{@missing}")

    absent = Path.join(ctx.fixture.codex_home, "missing.jsonl")

    assert upstream_error(pid, "getConversationSummary", %{"rolloutPath" => absent}) ==
             invalid("failed to resolve rollout path `#{absent}`: file does not exist")

    assert upstream_error(pid, "getConversationSummary", %{
             "rolloutPath" => ctx.fixture.codex_home
           }) ==
             invalid(
               "failed to resolve rollout path `#{ctx.fixture.codex_home}`: path is a directory"
             )

    for params <- [%{}, %{"conversationId" => "malformed"}, %{"rolloutPath" => 17}] do
      assert_invalid_wire(pid, "getConversationSummary", params)
    end

    assert loaded(pid) == []
    assert_idle(ctx, pid)
  end

  test "git diff uses owned local tracking refs and returns exact clean dirty and untracked facts",
       ctx do
    repo = Path.join(ctx.root, "local-repo")
    origin = Path.join(ctx.root, "local-origin.git")
    File.mkdir!(repo)
    File.mkdir!(origin)
    git(ctx, origin, ["init", "--bare", "--initial-branch=main"])
    git(ctx, repo, ["init", "--initial-branch=main"])
    git(ctx, repo, ["config", "user.name", "Synthetic fixture"])
    git(ctx, repo, ["config", "user.email", "fixture@example.invalid"])
    git(ctx, repo, ["config", "commit.gpgsign", "false"])
    git(ctx, repo, ["config", "core.hooksPath", "/dev/null"])
    File.write!(Path.join(repo, "tracked.txt"), "original\n")
    git(ctx, repo, ["add", "tracked.txt"])
    git(ctx, repo, ["commit", "-m", "Owned local baseline"])
    base = git(ctx, repo, ["rev-parse", "HEAD"])
    git(ctx, repo, ["remote", "add", "origin", origin])
    git(ctx, repo, ["update-ref", "refs/remotes/origin/main", base])
    git(ctx, repo, ["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main"])
    pid = start(ctx, experimental: false)
    assert call(pid, "gitDiffToRemote", %{"cwd" => repo}) == %{"sha" => base, "diff" => ""}
    File.write!(Path.join(repo, "tracked.txt"), "changed λ\n")
    File.write!(Path.join(repo, "new.txt"), "untracked 🙂\n")
    result = call(pid, "gitDiffToRemote", %{"cwd" => repo})
    assert result["sha"] == base
    assert result["diff"] =~ "diff --git a/tracked.txt b/tracked.txt\n"
    assert result["diff"] =~ "-original\n+changed λ\n"
    assert result["diff"] =~ "diff --git a/new.txt b/new.txt\nnew file mode 100644\n"
    assert result["diff"] =~ "+untracked 🙂\n"
    assert result["diff"] == call(pid, "gitDiffToRemote", %{"cwd" => repo})["diff"]

    error = upstream_error(pid, "gitDiffToRemote", %{"cwd" => ctx.fixture.workspace})

    assert error ==
             invalid(
               "failed to compute git diff to remote for cwd: #{JSON.encode!(ctx.fixture.workspace)}"
             )

    assert_invalid_wire(pid, "gitDiffToRemote", %{"cwd" => 17})
    assert loaded(pid) == []
    assert_idle(ctx, pid)
  end

  defp named(ctx, pid, history) do
    id = thread(ctx, pid, %{"historyMode" => history})

    assert call(pid, "thread/name/set", %{"threadId" => id, "name" => "Owned no-turn history λ"}) ==
             %{}

    id
  end

  defp set_mode(pid, id, mode),
    do: call(pid, "thread/memoryMode/set", %{"threadId" => id, "mode" => mode})

  defp summary(pid, params), do: call(pid, "getConversationSummary", params)["summary"]
  defp loaded(pid), do: call(pid, "thread/loaded/list", %{})["data"]

  defp latest_meta(path, id) do
    metadata =
      path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&JSON.decode!/1)
      |> Enum.filter(&(&1["type"] == "session_meta" and &1["payload"]["id"] == id))

    assert metadata != []
    List.last(metadata)["payload"]
  end

  defp stored_mode(ctx, id) do
    path = Path.join(ctx.fixture.codex_home, "state_5.sqlite")
    assert_owned(ctx, path)
    assert File.regular?(path)

    script = """
    import json, pathlib, sqlite3, sys
    database = pathlib.Path(sys.argv[1]).resolve().as_uri() + '?mode=ro'
    with sqlite3.connect(database, uri=True, timeout=1) as connection:
        row = connection.execute('SELECT memory_mode FROM threads WHERE id = ?', (sys.argv[2],)).fetchone()
        print(json.dumps(row[0] if row else None))
    """

    {output, status} = System.cmd("python3", ["-c", script, path, id], stderr_to_stdout: true)
    assert status == 0, "read-only owned SQLite observation failed: #{output}"
    JSON.decode!(String.trim(output))
  end

  defp assert_owned(ctx, path) do
    assert is_binary(path)
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.root) <> "/")
  end

  defp assert_invalid_wire(pid, method, params) do
    error = upstream_error(pid, method, params, validation: :wire)
    assert error["code"] == -32_600
    assert String.starts_with?(error["message"], "Invalid request: ")
  end

  defp git(ctx, cwd, args) do
    {output, status} =
      System.cmd("git", ["-c", "color.ui=false", "-c", "core.hooksPath=/dev/null" | args],
        cd: cwd,
        env: [
          {"HOME", ctx.fixture.home},
          {"GIT_CONFIG_NOSYSTEM", "1"},
          {"GIT_CONFIG_GLOBAL", "/dev/null"},
          {"GIT_TERMINAL_PROMPT", "0"}
        ],
        stderr_to_stdout: true
      )

    assert status == 0, "owned local Git fixture failed: #{output}"
    String.trim(output)
  end

  defp await(predicate), do: await(predicate, System.monotonic_time(:millisecond) + 20_000)

  defp await(predicate, deadline) do
    unless predicate.() do
      assert System.monotonic_time(:millisecond) < deadline,
             "native compression completion deadline"

      receive do
      after
        10 -> :ok
      end

      await(predicate, deadline)
    end
  end

  defp invalid(message), do: %{"code" => -32_600, "message" => message}

  defp assert_idle(ctx, pid) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
  end
end
