defmodule SamgitaCodexDriver.MethodFamiliesTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @missing_thread "00000000-0000-0000-0000-000000000000"

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: CODEX_BINARY must select the immutable pinned executable"

    root =
      Path.join(System.tmp_dir!(), "samgita-codex-families-#{System.unique_integer([:positive])}")

    fixture = ModelFixture.start(root, "assistant")

    on_exit(fn ->
      ModelFixture.close(fixture)
      File.rm_rf!(root)
    end)

    %{binary: binary, fixture: fixture, root: root}
  end

  defp start(context, opts \\ []) do
    env =
      Map.merge(
        %{
          "HOME" => context.fixture.home,
          "CODEX_HOME" => context.fixture.codex_home,
          "PATH" => context.fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
          "RUST_LOG" => "off"
        },
        Keyword.get(opts, :env, %{})
      )

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: context.binary,
             args: ["app-server", "--listen", "stdio://"],
             cwd: context.fixture.workspace,
             env: env
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_method_families", "version" => "0.1.0"},
               %{"experimentalApi" => Keyword.get(opts, :experimental, true)}
             )

    pid
  end

  defp call(pid, method, params \\ %{}, opts \\ []) do
    assert {:ok, %{"id" => id, "result" => result}} = Session.request(pid, method, params, opts)
    assert is_integer(id) or is_binary(id)
    result
  end

  defp upstream_error(pid, method, params, opts \\ []) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             Session.request(pid, method, params, opts)

    assert is_integer(error["code"]) and error["code"] < 0
    assert is_binary(error["message"])
    error
  end

  defp events_until(pid, predicate, acc \\ [], deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 15_000
    assert {:ok, events} = Session.drain(pid)

    refute Enum.any?(events, &(&1.kind == :server_request)),
           "unexpected interaction in local method fixture"

    acc = acc ++ events

    cond do
      predicate.(acc) ->
        acc

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("native event deadline: #{inspect(Session.status(pid))}")

      true ->
        assert Session.status(pid).phase == :ready

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
        after
          10 -> :ok
        end

        events_until(pid, predicate, acc, deadline)
    end
  end

  defp notification(events, method, predicate \\ fn _ -> true end) do
    Enum.find_value(events, fn event ->
      if event.wire["method"] == method and predicate.(event.wire["params"]),
        do: event.wire["params"]
    end)
  end

  defp thread(pid, fixture) do
    call(pid, "thread/start", %{
      "cwd" => fixture.workspace,
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "sandbox" => "read-only",
      "approvalPolicy" => "on-request",
      "ephemeral" => false
    })["thread"]
  end

  defp turn(pid, thread_id, text) do
    turn =
      call(pid, "turn/start", %{
        "threadId" => thread_id,
        "input" => [%{"type" => "text", "text" => text}]
      })["turn"]

    events =
      events_until(pid, fn events ->
        notification(events, "turn/completed", &(&1["turn"]["id"] == turn["id"]))
      end)

    completed = notification(events, "turn/completed", &(&1["turn"]["id"] == turn["id"]))
    assert completed["threadId"] == thread_id
    assert completed["turn"]["status"] == "completed"
    {turn["id"], events}
  end

  test "native fs CRUD preserves arbitrary bytes, copy effects and symlink metadata", context do
    pid = start(context)
    directory = Path.join(context.fixture.workspace, "nested/source")
    path = Path.join(directory, "binary.bin")
    bytes = <<0, 255, 195, 40, 10, 0>>
    assert call(pid, "fs/createDirectory", %{"path" => directory}) == %{}
    assert File.dir?(directory)

    assert call(pid, "fs/writeFile", %{"path" => path, "dataBase64" => Base.encode64(bytes)}) ==
             %{}

    assert File.read!(path) == bytes
    assert call(pid, "fs/readFile", %{"path" => path}) == %{"dataBase64" => Base.encode64(bytes)}
    metadata = call(pid, "fs/getMetadata", %{"path" => path})
    assert %{"isFile" => true, "isDirectory" => false, "isSymlink" => false} = metadata
    assert metadata["modifiedAtMs"] > 0
    link = Path.join(directory, "binary-link")
    File.ln_s!(path, link)

    assert %{"isFile" => true, "isSymlink" => true} =
             call(pid, "fs/getMetadata", %{"path" => link})

    entries = call(pid, "fs/readDirectory", %{"path" => directory})["entries"]
    assert Enum.any?(entries, &(&1["fileName"] == "binary.bin" and &1["isFile"]))
    copy = Path.join(context.fixture.workspace, "copy")

    assert call(pid, "fs/copy", %{
             "sourcePath" => directory,
             "destinationPath" => copy,
             "recursive" => true
           }) == %{}

    assert File.read!(Path.join(copy, "binary.bin")) == bytes
    assert call(pid, "fs/remove", %{"path" => copy, "recursive" => true, "force" => false}) == %{}
    refute File.exists?(copy)
    error = upstream_error(pid, "fs/readFile", %{"path" => Path.join(copy, "missing")})
    assert error["message"] =~ "No such file"
    error = upstream_error(pid, "fs/writeFile", %{"path" => path, "dataBase64" => "%%%"})
    assert error["message"] =~ "base64"
    assert File.read!(path) == bytes
  end

  test "fs watches associate real changes with connection-scoped watch IDs", context do
    pid = start(context)
    path = Path.join(context.fixture.workspace, "watched.txt")
    File.write!(path, "before")

    assert call(pid, "fs/watch", %{"path" => path, "watchId" => "fixture-watch"}) == %{
             "path" => path
           }

    File.write!(path, "after")

    events =
      events_until(
        pid,
        &notification(&1, "fs/changed", fn p -> p["watchId"] == "fixture-watch" end)
      )

    assert path in notification(events, "fs/changed")["changedPaths"]
    assert call(pid, "fs/unwatch", %{"watchId" => "fixture-watch"}) == %{}
    assert call(pid, "fs/unwatch", %{"watchId" => "fixture-watch"}) == %{}
  end

  test "disabled local environment returns upstream errors for fs and process operations",
       context do
    pid = start(context, env: %{"CODEX_EXEC_SERVER_URL" => "none"})

    assert upstream_error(pid, "fs/readFile", %{
             "path" => Path.join(context.fixture.workspace, "x")
           })["message"] == "local filesystem is not configured"

    assert upstream_error(pid, "process/spawn", %{
             "processHandle" => "disabled",
             "cwd" => context.fixture.workspace,
             "command" => [Path.join(context.fixture.bin, "sh"), "-c", "printf synthetic"]
           })["message"] == "local environment is not configured"

    assert Session.status(pid).phase == :ready
  end

  test "buffered command exec honors argv, cwd, environment and output cap", context do
    pid = start(context)

    command = [
      Path.join(context.fixture.bin, "sh"),
      "-c",
      "printf '%s|%s' \"$PWD\" \"$FIXTURE_VALUE\"; printf stderr >&2"
    ]

    result =
      call(pid, "command/exec", %{
        "command" => command,
        "cwd" => context.fixture.workspace,
        "env" => %{"FIXTURE_VALUE" => "synthetic"},
        "sandboxPolicy" => %{"type" => "dangerFullAccess"},
        "timeoutMs" => 2_000
      })

    assert result == %{
             "exitCode" => 0,
             "stdout" => context.fixture.workspace <> "|synthetic",
             "stderr" => "stderr"
           }

    capped =
      call(pid, "command/exec", %{
        "command" => [
          Path.join(context.fixture.bin, "sh"),
          "-c",
          "printf abcdef; printf 123456 >&2"
        ],
        "sandboxPolicy" => %{"type" => "dangerFullAccess"},
        "outputBytesCap" => 3
      })

    assert capped == %{"exitCode" => 0, "stdout" => "abc", "stderr" => "123"}

    error =
      upstream_error(pid, "command/exec", %{"command" => [], "cwd" => context.fixture.workspace})

    assert error["message"] =~ "command"

    error =
      upstream_error(pid, "command/exec/write", %{
        "processId" => "missing",
        "deltaBase64" => Base.encode64("x")
      })

    assert error["message"] =~ "missing"
  end

  test "process spawn streams stdin and output with exact handle and exit association", context do
    pid = start(context)
    handle = "fixture-stream"

    assert call(pid, "process/spawn", %{
             "processHandle" => handle,
             "cwd" => context.fixture.workspace,
             "command" => [
               Path.join(context.fixture.bin, "sh"),
               "-c",
               "read value; printf 'out:%s' \"$value\"; printf err >&2"
             ],
             "streamStdin" => true,
             "streamStdoutStderr" => true,
             "timeoutMs" => 5_000
           }) == %{}

    assert call(pid, "process/writeStdin", %{
             "processHandle" => handle,
             "deltaBase64" => Base.encode64("synthetic\n"),
             "closeStdin" => true
           }) == %{}

    events =
      events_until(
        pid,
        &notification(&1, "process/exited", fn p -> p["processHandle"] == handle end)
      )

    exited = notification(events, "process/exited")

    assert %{
             "processHandle" => ^handle,
             "exitCode" => 0,
             "stdout" => "",
             "stderr" => "",
             "stdoutCapReached" => false
           } = exited

    output = for e <- events, e.wire["method"] == "process/outputDelta", do: e.wire["params"]
    assert Enum.all?(output, &(&1["processHandle"] == handle and &1["capReached"] == false))

    for {stream, expected} <- [{"stdout", "out:synthetic"}, {"stderr", "err"}] do
      assert output
             |> Enum.filter(&(&1["stream"] == stream))
             |> Enum.map_join(&Base.decode64!(&1["deltaBase64"])) == expected
    end

    error =
      upstream_error(pid, "process/writeStdin", %{
        "processHandle" => handle,
        "deltaBase64" => Base.encode64("late")
      })

    assert error["message"] =~ handle
  end

  test "process handles reject duplicate running owners and kill only the selected process",
       context do
    pid = start(context)

    params = %{
      "processHandle" => "fixture-blocked",
      "cwd" => context.fixture.workspace,
      "command" => [Path.join(context.fixture.bin, "sh"), "-c", "read value"],
      "streamStdin" => true,
      "timeoutMs" => 5_000
    }

    assert call(pid, "process/spawn", params) == %{}
    error = upstream_error(pid, "process/spawn", params)
    assert error["message"] =~ "fixture-blocked"
    assert call(pid, "process/kill", %{"processHandle" => "fixture-blocked"}) == %{}

    events =
      events_until(
        pid,
        &notification(&1, "process/exited", fn p -> p["processHandle"] == "fixture-blocked" end)
      )

    refute notification(events, "process/exited")["exitCode"] == 0

    assert upstream_error(pid, "process/kill", %{"processHandle" => "never-created"})["message"] =~
             "never-created"
  end

  test "process output cap preserves distinct per-stream truncation metadata", context do
    pid = start(context)

    call(pid, "process/spawn", %{
      "processHandle" => "capped",
      "cwd" => context.fixture.workspace,
      "command" => [
        Path.join(context.fixture.bin, "sh"),
        "-c",
        "printf abcdef; printf 123456 >&2"
      ],
      "outputBytesCap" => 3
    })

    events =
      events_until(
        pid,
        &notification(&1, "process/exited", fn p -> p["processHandle"] == "capped" end)
      )

    assert %{
             "stdout" => "abc",
             "stderr" => "123",
             "stdoutCapReached" => true,
             "stderrCapReached" => true,
             "processHandle" => "capped",
             "exitCode" => 0
           } = notification(events, "process/exited")
  end

  test "experimental process capability is rejected locally and by actual upstream when disabled",
       context do
    pid = start(context, experimental: false)

    params = %{
      "processHandle" => "disabled-gate",
      "cwd" => context.fixture.workspace,
      "command" => [Path.join(context.fixture.bin, "sh"), "-c", "printf synthetic"]
    }

    assert {:error, %Error{code: :experimental_api_required}} =
             Session.request(pid, "process/spawn", params)

    error = upstream_error(pid, "process/spawn", params, validation: :wire)
    assert error["message"] =~ "experimental"
    assert Session.status(pid).pending == 0
  end

  test "configuration writes persist, batch atomically and reject stale file versions", context do
    pid = start(context)

    before =
      call(pid, "config/read", %{"includeLayers" => true, "cwd" => context.fixture.workspace})

    assert before["config"]["model"] == "mock-model"
    assert before["config"]["model_provider"] == "fixture"
    assert is_list(before["layers"]) and before["layers"] != []
    path = Path.join(context.fixture.codex_home, "config.toml")

    write =
      call(pid, "config/value/write", %{
        "keyPath" => "model_reasoning_effort",
        "value" => "high",
        "mergeStrategy" => "replace",
        "filePath" => path
      })

    assert %{"status" => "ok", "filePath" => ^path, "version" => version} = write
    assert String.starts_with?(version, "sha256:")
    persisted = File.read!(path)
    assert persisted =~ "model_reasoning_effort = \"high\""

    error =
      upstream_error(pid, "config/value/write", %{
        "keyPath" => "model_reasoning_effort",
        "value" => "low",
        "mergeStrategy" => "replace",
        "expectedVersion" => "sha256:stale"
      })

    assert error["data"]["config_write_error_code"] == "configVersionConflict"
    assert File.read!(path) == persisted

    batch =
      call(pid, "config/batchWrite", %{
        "expectedVersion" => version,
        "reloadUserConfig" => false,
        "edits" => [
          %{
            "keyPath" => "model_reasoning_effort",
            "value" => "medium",
            "mergeStrategy" => "replace"
          },
          %{
            "keyPath" => "desktop.appearanceTheme",
            "value" => "dark",
            "mergeStrategy" => "replace"
          }
        ]
      })

    refute batch["version"] == version
    read = call(pid, "config/read", %{"includeLayers" => false})
    assert read["config"]["model_reasoning_effort"] == "medium"
    assert read["config"]["desktop"]["appearanceTheme"] == "dark"
    assert read["layers"] == nil
    assert %{"requirements" => nil} = call(pid, "configRequirements/read", nil)
  end

  test "skills list and config reflect synthetic disk metadata and explicit enablement",
       context do
    skill = Path.join(context.fixture.codex_home, "skills/fixture-skill/SKILL.md")
    File.mkdir_p!(Path.dirname(skill))

    File.write!(
      skill,
      "---\nname: fixture-skill\ndescription: Synthetic local skill\n---\n\nOnly fixture content.\n"
    )

    pid = start(context)
    config_path = Path.join(context.fixture.codex_home, "config.toml")
    original_config = File.read!(config_path)
    params = %{"cwds" => [context.fixture.workspace], "forceReload" => true}
    listing = call(pid, "skills/list", params)
    assert [%{"cwd" => cwd, "skills" => skills, "errors" => []}] = listing["data"]
    assert cwd == context.fixture.workspace

    assert %{
             "path" => ^skill,
             "enabled" => true,
             "description" => "Synthetic local skill",
             "scope" => "user"
           } = Enum.find(skills, &(&1["name"] == "fixture-skill"))

    assert call(pid, "skills/config/write", %{"path" => skill, "enabled" => false}) == %{
             "effectiveEnabled" => false
           }

    assert File.read!(config_path) =~ "enabled = false"
    listing = call(pid, "skills/list", params)

    refute listing["data"]
           |> hd()
           |> Map.fetch!("skills")
           |> Enum.find(&(&1["name"] == "fixture-skill"))
           |> Map.fetch!("enabled")

    assert call(pid, "skills/config/write", %{"path" => skill, "enabled" => true}) == %{
             "effectiveEnabled" => true
           }

    assert File.read!(config_path) == original_config
    listing = call(pid, "skills/list", params)

    assert listing["data"]
           |> hd()
           |> Map.fetch!("skills")
           |> Enum.find(&(&1["name"] == "fixture-skill"))
           |> Map.fetch!("enabled")

    error = upstream_error(pid, "skills/config/write", %{"enabled" => false})
    assert error["message"] =~ "path"
  end

  test "model catalog pagination and provider capabilities preserve actual local profile",
       context do
    pid = start(context)
    first = call(pid, "model/list", %{"limit" => 1, "includeHidden" => true})
    assert [model] = first["data"]
    assert is_binary(model["id"]) and is_binary(model["model"])
    assert is_list(model["supportedReasoningEfforts"])
    assert is_binary(first["nextCursor"])

    second =
      call(pid, "model/list", %{
        "limit" => 1,
        "includeHidden" => true,
        "cursor" => first["nextCursor"]
      })

    assert [next_model] = second["data"]
    refute next_model["id"] == model["id"]

    assert upstream_error(pid, "model/list", %{"cursor" => "not-a-valid-cursor"})["message"] =~
             "cursor"

    # Provider upper bounds default to true; disabled web_search is a turn setting.
    # This does not assert this fixture implements hosted search/image generation.
    assert %{"imageGeneration" => true, "webSearch" => true} =
             call(pid, "modelProvider/capabilities/read")

    assert %{"account" => nil, "requiresOpenaiAuth" => false} =
             call(pid, "account/read", %{"refreshToken" => false})
  end

  test "skill extra roots change runtime discovery and notify without altering user configuration",
       context do
    pid = start(context)
    root = Path.join(context.fixture.workspace, "runtime-skills")
    path = Path.join(root, "runtime-fixture/SKILL.md")
    File.mkdir_p!(Path.dirname(path))

    File.write!(
      path,
      "---\nname: runtime-fixture\ndescription: Runtime synthetic skill\n---\n\nFixture only.\n"
    )

    config = File.read!(Path.join(context.fixture.codex_home, "config.toml"))
    assert call(pid, "skills/extraRoots/set", %{"extraRoots" => [root]}) == %{}
    events_until(pid, &notification(&1, "skills/changed"))
    params = %{"cwds" => [context.fixture.workspace], "forceReload" => true}
    skills = call(pid, "skills/list", params)["data"] |> hd() |> Map.fetch!("skills")
    assert Enum.any?(skills, &(&1["name"] == "runtime-fixture" and &1["path"] == path))
    assert call(pid, "skills/extraRoots/set", %{"extraRoots" => []}) == %{}
    events_until(pid, &notification(&1, "skills/changed"))
    skills = call(pid, "skills/list", params)["data"] |> hd() |> Map.fetch!("skills")
    refute Enum.any?(skills, &(&1["name"] == "runtime-fixture"))
    assert File.read!(Path.join(context.fixture.codex_home, "config.toml")) == config
  end

  test "persistent thread history paginates turns and items then forks and reverts without reexecution",
       context do
    pid = start(context)
    original = thread(pid, context.fixture)
    id = original["id"]
    {first_turn, _} = turn(pid, id, "Synthetic first turn")
    {second_turn, _} = turn(pid, id, "Synthetic second turn")
    read = call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})
    assert Enum.map(read["thread"]["turns"], & &1["id"]) == [first_turn, second_turn]

    page =
      call(pid, "thread/turns/list", %{
        "threadId" => id,
        "limit" => 1,
        "itemsView" => "full",
        "sortDirection" => "asc"
      })

    assert [%{"id" => ^first_turn, "items" => [_ | _]}] = page["data"]

    next =
      call(pid, "thread/turns/list", %{
        "threadId" => id,
        "limit" => 1,
        "cursor" => page["nextCursor"],
        "sortDirection" => "asc"
      })

    assert [%{"id" => ^second_turn}] = next["data"]

    items =
      call(pid, "thread/items/list", %{"threadId" => id, "turnId" => first_turn, "limit" => 100})[
        "data"
      ]

    assert Enum.all?(items, &(&1["turnId"] == first_turn))
    assistant = Enum.find(items, &(&1["item"]["type"] == "agentMessage"))
    assert assistant["item"]["text"] == "Deterministic local fixture answer"

    assert call(pid, "thread/items/read", %{
             "threadId" => id,
             "turnId" => first_turn,
             "itemIds" => [assistant["item"]["id"]]
           })["data"] == [assistant]

    forked =
      call(pid, "thread/fork", %{
        "threadId" => id,
        "lastTurnId" => first_turn,
        "cwd" => context.fixture.workspace
      })["thread"]

    refute forked["id"] == id
    assert forked["forkedFromId"] == id
    fork_read = call(pid, "thread/read", %{"threadId" => forked["id"], "includeTurns" => true})
    assert length(fork_read["thread"]["turns"]) == 1

    assert call(pid, "thread/name/set", %{"threadId" => forked["id"], "name" => "Synthetic fork"}) ==
             %{}

    assert call(pid, "thread/read", %{"threadId" => forked["id"]})["thread"]["name"] ==
             "Synthetic fork"

    reverted = call(pid, "thread/revert", %{"threadId" => id, "beforeTurnId" => second_turn})
    assert reverted["thread"]["id"] == id
    assert reverted["thread"]["turns"] == []
    assert [%{"id" => ^first_turn}] = call(pid, "thread/turns/list", %{"threadId" => id})["data"]
    assert length(ModelFixture.requests(context.fixture)) == 2
  end

  test "archive, unarchive, subscription and deletion preserve separate thread state", context do
    pid = start(context)
    id = thread(pid, context.fixture)["id"]
    turn(pid, id, "Synthetic persisted lifecycle")
    assert id in call(pid, "thread/loaded/list")["data"]
    assert call(pid, "thread/unsubscribe", %{"threadId" => id}) == %{"status" => "unsubscribed"}
    resumed = call(pid, "thread/resume", %{"threadId" => id})
    assert resumed["thread"]["id"] == id
    assert call(pid, "thread/archive", %{"threadId" => id}) == %{}

    archived =
      call(pid, "thread/list", %{"archived" => true, "cwd" => context.fixture.workspace})["data"]

    assert Enum.any?(archived, &(&1["id"] == id))

    refute Enum.any?(
             call(pid, "thread/list", %{"cwd" => context.fixture.workspace})["data"],
             &(&1["id"] == id)
           )

    assert call(pid, "thread/unarchive", %{"threadId" => id})["thread"]["id"] == id

    assert Enum.any?(
             call(pid, "thread/list", %{"cwd" => context.fixture.workspace})["data"],
             &(&1["id"] == id)
           )

    assert call(pid, "thread/delete", %{"threadId" => id}) == %{}

    refute Enum.any?(
             call(pid, "thread/list", %{"cwd" => context.fixture.workspace})["data"],
             &(&1["id"] == id)
           )

    assert upstream_error(pid, "thread/read", %{"threadId" => id})["message"] =~ id
    assert length(ModelFixture.requests(context.fixture)) == 1
  end

  test "thread invalid state and incompatible filters remain structured upstream errors",
       context do
    pid = start(context)

    for method <- [
          "thread/read",
          "thread/resume",
          "thread/archive",
          "thread/unarchive",
          "thread/delete"
        ] do
      error = upstream_error(pid, method, %{"threadId" => @missing_thread})
      assert error["message"] =~ @missing_thread
    end

    error =
      upstream_error(pid, "thread/list", %{"originators" => ["synthetic-unsupported-local"]})

    assert error["message"] =~ "originator"

    error =
      upstream_error(pid, "thread/list", %{
        "parentThreadId" => @missing_thread,
        "ancestorThreadId" => @missing_thread
      })

    assert error["message"] =~ "parentThreadId"
    assert Session.status(pid).pending == 0
    assert Session.status(pid).phase == :ready
  end
end
