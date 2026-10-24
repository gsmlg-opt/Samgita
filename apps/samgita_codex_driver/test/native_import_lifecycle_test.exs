defmodule SamgitaCodexDriver.NativeImportLifecycleTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  @moduletag :real_codex
  @moduletag timeout: 60_000

  setup tags do
    TurnFixture.setup(tags)
  end

  test "owned home and repository detection honor migration source independently of attribution",
       ctx do
    repo = repository(ctx, "detect-repository")
    nested = Path.join(repo, "nested")
    File.mkdir_p!(nested)
    put(ctx, Path.join(ctx.fixture.home, ".claude/CLAUDE.md"), "Claude home guidance")
    put(ctx, Path.join(repo, "CLAUDE.md"), "Claude repository guidance")

    put(
      ctx,
      Path.join(ctx.fixture.home, ".cursor/cli-config.json"),
      JSON.encode!(%{"env" => %{"SYNTHETIC_IMPORT_SOURCE" => "secondary"}})
    )

    config_before = File.read!(config_path(ctx))
    pid = start(ctx)

    params = %{
      "includeHome" => true,
      "cwds" => [nested],
      "maxSessionAgeDays" => 0,
      "maxSessions" => 0
    }

    primary = call(pid, "externalAgentConfig/detect", params)
    assert primary["connectors"] == []

    assert Enum.map(primary["items"], &{&1["itemType"], &1["cwd"]}) == [
             {"AGENTS_MD", nil},
             {"AGENTS_MD", repo}
           ]

    assert Enum.all?(primary["items"], &(is_binary(&1["description"]) and &1["details"] == nil))

    for selectors <- [
          %{"migrationSource" => "claude-code"},
          %{"migrationSource" => "unknown-synthetic-source"},
          %{"source" => "cursor"}
        ] do
      assert call(pid, "externalAgentConfig/detect", Map.merge(params, selectors)) == primary
    end

    repo_only = call(pid, "externalAgentConfig/detect", %{params | "includeHome" => false})
    assert Enum.map(repo_only["items"], & &1["cwd"]) == [repo]

    secondary =
      call(pid, "externalAgentConfig/detect", %{
        "includeHome" => true,
        "migrationSource" => "CuRsOr"
      })

    assert [%{"itemType" => "CONFIG", "cwd" => nil, "details" => nil}] = secondary["items"]
    assert secondary["connectors"] == []
    assert File.read!(config_path(ctx)) == config_before
    refute File.exists?(Path.join(ctx.fixture.codex_home, "AGENTS.md"))
    refute File.exists?(Path.join(repo, "AGENTS.md"))

    {id, results, _events} =
      run_import(pid, secondary["items"], %{
        "migrationSource" => "cursor",
        "source" => "claude-code",
        "providerId" => "opaque-secondary-provider"
      })

    assert [%{"itemType" => "CONFIG", "successes" => [success], "failures" => []}] = results

    assert success ==
             success(
               "CONFIG",
               nil,
               Path.join(ctx.fixture.home, ".cursor/cli-config.json"),
               config_path(ctx)
             )

    assert File.read!(config_path(ctx)) =~ "SYNTHETIC_IMPORT_SOURCE = \"secondary\""
    assert history(pid, id)["providerId"] == "opaque-secondary-provider"

    assert call(pid, "externalAgentConfig/detect", %{
             "includeHome" => true,
             "migrationSource" => "cursor"
           })["items"] == []

    assert_idle(ctx, pid)
  end

  test "repository instruction imports correlate completion preserve targets and survive restart",
       ctx do
    repo = repository(ctx, "instruction-repository")
    protected = repository(ctx, "protected-repository")
    nested = Path.join(repo, "nested/deeper")
    File.mkdir_p!(nested)
    source = Path.join(repo, "CLAUDE.md")
    original = "Claude guidance. See CLAUDE.md and [Claude](https://claude.ai/CLAUDE.md).\n"
    put(ctx, source, original)
    put(ctx, Path.join(protected, "CLAUDE.md"), "Claude replacement must remain unused")
    put(ctx, Path.join(protected, "AGENTS.md"), "Preserved operator instructions")
    pid = start(ctx)

    detected =
      call(pid, "externalAgentConfig/detect", %{
        "includeHome" => false,
        "cwds" => [nested, protected]
      })["items"]

    assert [%{"itemType" => "AGENTS_MD", "cwd" => ^repo}] = detected
    selected = detected ++ [item("AGENTS_MD", protected)]

    {id, results, events} =
      run_import(pid, selected, %{"source" => "cursor", "providerId" => "synthetic-instructions"})

    expected = success("AGENTS_MD", repo, source, Path.join(repo, "AGENTS.md"))
    assert Enum.flat_map(results, & &1["successes"]) == [expected]
    assert Enum.all?(results, &(&1["itemType"] == "AGENTS_MD" and &1["failures"] == []))

    assert progress_updates(events, id) == [
             %{"itemType" => "AGENTS_MD", "successes" => [expected], "failures" => []},
             %{"itemType" => "AGENTS_MD", "successes" => [], "failures" => []}
           ]

    assert progress_results(events, id) == results

    assert File.read!(Path.join(repo, "AGENTS.md")) ==
             "Codex guidance. See AGENTS.md and [Codex](https://claude.ai/CLAUDE.md).\n"

    assert File.read!(source) == original
    assert File.read!(Path.join(protected, "AGENTS.md")) == "Preserved operator instructions"
    assert history(pid, id)["successes"] == [expected]
    {repeat_id, repeated, _events} = run_import(pid, selected)
    assert repeat_id != id
    assert Enum.all?(repeated, &(&1["successes"] == [] and &1["failures"] == []))

    assert call(pid, "externalAgentConfig/detect", %{
             "includeHome" => false,
             "cwds" => [repo, protected]
           })["items"] == []

    saved = histories(pid)
    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert histories(cold) == saved
    assert history(cold, id)["providerId"] == "synthetic-instructions"
    assert_idle(ctx, cold)
  end

  test "skill and command imports rewrite selected text copy binary assets and preserve collisions",
       ctx do
    source = Path.join(ctx.fixture.home, ".claude")
    target = Path.join(ctx.root, ".agents/skills")

    skill =
      "---\nname: imported-skill\ndescription: Synthetic import\n---\nClaude uses CLAUDE.md.\n"

    put(ctx, Path.join(source, "skills/imported-skill/SKILL.md"), skill)
    put(ctx, Path.join(source, "skills/imported-skill/asset.bin"), <<0, 1, 255>>)
    put(ctx, Path.join(source, "skills/preserved/SKILL.md"), "Claude source must remain unused")
    put(ctx, Path.join(target, "preserved/SKILL.md"), "Preserved skill target")
    put(ctx, Path.join(source, "commands/review.md"), "Review with Claude and CLAUDE.md.\n")
    put(ctx, Path.join(source, "commands/unsupported.md"), "Deploy $ARGUMENTS.\n")
    pid = start(ctx)
    detected = call(pid, "externalAgentConfig/detect", %{"includeHome" => true})["items"]
    assert Enum.map(detected, & &1["itemType"]) == ["SKILLS", "COMMANDS"]
    assert hd(detected)["details"]["skills"] == [%{"name" => "imported-skill"}]
    assert List.last(detected)["details"]["commands"] == [%{"name" => "source-command-review"}]
    {id, results, _events} = run_import(pid, detected)
    assert Enum.map(results, & &1["itemType"]) == ["SKILLS", "COMMANDS"]
    assert Enum.all?(results, &(&1["failures"] == [] and length(&1["successes"]) == 1))

    assert Enum.flat_map(results, & &1["successes"]) == [
             success("SKILLS", nil, "imported-skill", "imported-skill"),
             success("COMMANDS", nil, "source-command-review", "source-command-review")
           ]

    assert File.read!(Path.join(target, "imported-skill/SKILL.md")) ==
             "---\nname: imported-skill\ndescription: Synthetic import\n---\nCodex uses AGENTS.md.\n"

    assert File.read!(Path.join(target, "imported-skill/asset.bin")) == <<0, 1, 255>>
    command_skill = File.read!(Path.join(target, "source-command-review/SKILL.md"))
    assert command_skill =~ "name: \"source-command-review\""
    assert command_skill =~ "# source-command-review"
    assert command_skill =~ "Review with Codex and AGENTS.md.\n"
    assert File.read!(Path.join(target, "preserved/SKILL.md")) == "Preserved skill target"
    assert File.read!(Path.join(source, "skills/imported-skill/SKILL.md")) == skill
    refute File.exists?(Path.join(target, "source-command-unsupported"))
    assert call(pid, "externalAgentConfig/detect", %{"includeHome" => true})["items"] == []
    assert length(history(pid, id)["successes"]) == 2
    assert_idle(ctx, pid)
  end

  test "import revalidates redirected repository destinations after detection without touching sentinel",
       ctx do
    repo = repository(ctx, "redirected-repository")

    put(
      ctx,
      Path.join(repo, ".claude/settings.json"),
      JSON.encode!(%{"env" => %{"OWNED_ONLY" => "synthetic"}})
    )

    destination = Path.join(repo, ".codex")
    File.mkdir_p!(destination)
    sentinel = Path.join(ctx.root, "redirect-target")
    put(ctx, Path.join(sentinel, "config.toml"), "owned_sentinel = \"unchanged\"\n")
    pid = start(ctx)

    detected =
      call(pid, "externalAgentConfig/detect", %{"includeHome" => false, "cwds" => [repo]})[
        "items"
      ]

    assert [%{"itemType" => "CONFIG", "cwd" => ^repo}] = detected
    File.rmdir!(destination)
    File.ln_s!(sentinel, destination)
    {id, results, _events} = run_import(pid, detected)
    assert results == [%{"itemType" => "CONFIG", "successes" => [], "failures" => []}]
    assert File.read!(Path.join(sentinel, "config.toml")) == "owned_sentinel = \"unchanged\"\n"
    assert File.ls!(sentinel) == ["config.toml"]
    assert history(pid, id)["successes"] == []

    assert call(pid, "externalAgentConfig/detect", %{"includeHome" => false, "cwds" => [repo]})[
             "items"
           ] == []

    assert_idle(ctx, pid)
  end

  test "mixed import preserves success and exact config and unapproved-session failure taxonomy",
       ctx do
    invalid = repository(ctx, "invalid-config-repository")
    valid = repository(ctx, "valid-instructions-repository")

    put(
      ctx,
      Path.join(invalid, ".claude/settings.json"),
      JSON.encode!(%{"env" => %{"SYNTHETIC_IMPORT" => "yes"}})
    )

    put(ctx, Path.join(valid, "CLAUDE.md"), "Claude valid instructions")
    unapproved = Path.join(ctx.root, "unapproved-session.jsonl")
    put(ctx, unapproved, "Synthetic out-of-scope session must not be parsed\n")
    File.mkdir_p!(Path.join(ctx.fixture.home, ".claude/projects/owned-empty"))
    pid = start(ctx)

    detected =
      call(pid, "externalAgentConfig/detect", %{
        "includeHome" => false,
        "cwds" => [invalid, valid]
      })["items"]

    assert Enum.map(detected, & &1["itemType"]) == ["CONFIG", "AGENTS_MD"]
    put(ctx, Path.join(invalid, ".codex/config.toml"), "invalid = [")

    selected =
      detected ++
        [
          Map.put(item("SESSIONS", ctx.fixture.workspace), "details", %{
            "sessions" => [
              %{
                "path" => unapproved,
                "cwd" => ctx.fixture.workspace,
                "title" => "Unapproved owned session"
              }
            ]
          })
        ]

    {id, results, events} = run_import(pid, selected, %{"providerId" => "mixed-provider"})

    assert Enum.map(progress_updates(events, id), & &1["itemType"]) == [
             "SESSIONS",
             "CONFIG",
             "AGENTS_MD"
           ]

    assert progress_results(events, id) == results
    config_result = Enum.find(results, &(&1["itemType"] == "CONFIG"))
    assert config_result["successes"] == []
    assert [failure] = config_result["failures"]

    assert Map.drop(failure, ["message"]) == %{
             "itemType" => "CONFIG",
             "cwd" => invalid,
             "errorType" => "invalid_existing_config",
             "subErrorType" => nil,
             "failureStage" => "import_request_failed",
             "source" => nil
           }

    assert failure["message"] =~ "invalid existing config.toml"
    session_result = Enum.find(results, &(&1["itemType"] == "SESSIONS"))
    assert session_result["successes"] == []

    assert session_result["failures"] == [
             %{
               "itemType" => "SESSIONS",
               "cwd" => nil,
               "errorType" => nil,
               "subErrorType" => "session_not_detected",
               "failureStage" => "session_missing",
               "message" => "external agent session was not detected for import: #{unapproved}",
               "source" => unapproved
             }
           ]

    assert Enum.find(results, &(&1["itemType"] == "AGENTS_MD"))["successes"] == [
             success(
               "AGENTS_MD",
               valid,
               Path.join(valid, "CLAUDE.md"),
               Path.join(valid, "AGENTS.md")
             )
           ]

    assert File.read!(Path.join(valid, "AGENTS.md")) == "Codex valid instructions"
    assert File.read!(Path.join(invalid, ".codex/config.toml")) == "invalid = ["
    assert File.read!(unapproved) == "Synthetic out-of-scope session must not be parsed\n"
    recorded = history(pid, id)
    assert recorded["providerId"] == "mixed-provider"
    assert recorded["failures"] == Enum.flat_map(results, & &1["failures"])
    assert recorded["successes"] == Enum.flat_map(results, & &1["successes"])
    assert call(pid, "thread/list", %{})["data"] == []
    assert_idle(ctx, pid)
  end

  test "externally recorded results retain provider title failures and ordering across cold restart",
       ctx do
    pid = start(ctx)
    source = Path.join(ctx.root, "record-only/source.jsonl")
    target = Path.join(ctx.root, "record-only/target")

    session_success =
      success("SESSIONS", ctx.fixture.workspace, source, target, "Synthetic session title")

    config_success =
      success("CONFIG", nil, "Synthetic source metadata", "Synthetic target metadata")

    failure = %{
      "itemType" => "COMMANDS",
      "cwd" => ctx.fixture.workspace,
      "errorType" => "synthetic_error",
      "subErrorType" => "synthetic_subtype",
      "failureStage" => "synthetic_stage",
      "message" => "Synthetic externally reported failure",
      "source" => source
    }

    params = %{
      "providerId" => "record-only-provider",
      "itemTypeResults" => [
        %{"itemType" => "SESSIONS", "successes" => [session_success], "failures" => []},
        %{"itemType" => "CONFIG", "successes" => [config_success], "failures" => [failure]}
      ]
    }

    id = call(pid, "externalAgentConfig/import/recordHistory", params)["importId"]
    assert_uuid(id)
    recorded = history(pid, id)
    assert recorded["providerId"] == "record-only-provider"
    assert recorded["successes"] == [session_success, config_success]
    assert recorded["failures"] == [failure]
    assert recorded["completedAtMs"] > 0

    second =
      call(pid, "externalAgentConfig/import/recordHistory", %{
        params
        | "providerId" => "another-provider",
          "itemTypeResults" => []
      })["importId"]

    assert_uuid(second)
    assert second != id
    records = histories(pid)
    assert records["connectors"] == []
    assert length(records["data"]) == 2

    assert records["data"] ==
             Enum.sort_by(records["data"], &{-&1["completedAtMs"], &1["importId"]})

    refute File.exists?(source)
    refute File.exists?(target)
    assert call(pid, "thread/list", %{})["data"] == []
    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert histories(cold) == records
    refute File.exists?(source)
    refute File.exists?(target)
    assert_idle(ctx, cold)
  end

  test "hooks metadata preserves handler fields cwd ordering feature gates and isolated load errors",
       ctx do
    off = repository(ctx, "hooks-disabled-repository")
    broken = repository(ctx, "hooks-broken-repository")
    put(ctx, Path.join(off, ".codex/config.toml"), "[features]\nhooks = false\n")
    put(ctx, Path.join(broken, ".codex/config.toml"), "invalid = [")
    sentinel = Path.join(ctx.root, "hook-command-must-not-run")
    command = "printf executed > #{sentinel}"

    append_config(ctx, """
    [features]
    hooks = true
    plugins = false
    [hooks]
    [[hooks.PreToolUse]]
    matcher = "Bash"
    [[hooks.PreToolUse.hooks]]
    type = "command"
    command = #{JSON.encode!(command)}
    timeout = 5
    async = true
    statusMessage = "Synthetic listed hook"
    additionalContextLimit = 4096
    [projects.#{JSON.encode!(off)}]
    trust_level = "trusted"
    [projects.#{JSON.encode!(broken)}]
    trust_level = "trusted"
    """)

    original = File.read!(config_path(ctx))
    pid = start(ctx)
    first = call(pid, "hooks/list", %{})["data"]
    assert first == call(pid, "hooks/list", %{"cwds" => []})["data"]
    assert [%{"cwd" => cwd, "hooks" => [metadata], "warnings" => [], "errors" => []}] = first
    assert cwd == ctx.fixture.workspace

    assert Map.drop(metadata, ["currentHash"]) == %{
             "key" => "#{config_path(ctx)}:pre_tool_use:0:0",
             "eventName" => "preToolUse",
             "handlerType" => "command",
             "command" => command,
             "async" => true,
             "matcher" => "Bash",
             "timeoutSec" => 5,
             "statusMessage" => "Synthetic listed hook",
             "additionalContextLimit" => 4096,
             "sourcePath" => config_path(ctx),
             "source" => "user",
             "pluginId" => nil,
             "displayOrder" => 0,
             "enabled" => true,
             "isManaged" => false,
             "trustStatus" => "untrusted"
           }

    assert is_binary(metadata["currentHash"]) and byte_size(metadata["currentHash"]) > 0
    requested = [ctx.fixture.workspace, off, broken, ctx.fixture.workspace]
    entries = call(pid, "hooks/list", %{"cwds" => requested})["data"]
    assert Enum.map(entries, & &1["cwd"]) == requested
    assert hd(entries) == hd(first)
    assert List.last(entries) == hd(first)
    assert Enum.at(entries, 1) == %{"cwd" => off, "hooks" => [], "warnings" => [], "errors" => []}

    assert %{"cwd" => ^broken, "hooks" => [], "warnings" => [], "errors" => [error]} =
             Enum.at(entries, 2)

    assert error["path"] == broken
    assert error["message"] =~ "config.toml"
    assert File.read!(config_path(ctx)) == original
    refute File.exists?(sentinel)
    assert_idle(ctx, pid)
  end

  test "collaboration presets experimental gates stable methods and malformed import inputs retain native semantics",
       ctx do
    for capability <- [:absent, false] do
      pid = start(ctx, capability)
      error = upstream_error(pid, "collaborationMode/list", %{})
      assert error["code"] == -32_600
      assert error["message"] =~ "experimentalApi"

      assert call(pid, "externalAgentConfig/detect", %{
               "includeHome" => false,
               "cwds" => [ctx.fixture.workspace]
             }) == %{"items" => [], "connectors" => []}

      empty = call(pid, "externalAgentConfig/import", %{"migrationItems" => []})["importId"]
      assert_uuid(empty)
      refute Enum.any?(histories(pid)["data"], &(&1["importId"] == empty))

      recorded =
        call(pid, "externalAgentConfig/import/recordHistory", %{
          "providerId" => "stable-api",
          "itemTypeResults" => []
        })["importId"]

      assert_uuid(recorded)
      assert history(pid, recorded)["providerId"] == "stable-api"

      assert [%{"cwd" => cwd, "hooks" => [], "warnings" => [], "errors" => []}] =
               call(pid, "hooks/list", %{"cwds" => [ctx.fixture.workspace]})["data"]

      assert cwd == ctx.fixture.workspace
      assert {:ok, events} = Session.drain(pid)

      refute Enum.any?(
               events,
               &(&1.wire["method"] in [
                   "externalAgentConfig/import/progress",
                   "externalAgentConfig/import/completed"
                 ])
             )

      assert_idle(ctx, pid)
      assert :ok = Session.close(pid)
    end

    pid = start(ctx)

    assert call(pid, "collaborationMode/list", %{}) == %{
             "data" => [
               %{
                 "name" => "Plan",
                 "mode" => "plan",
                 "model" => nil,
                 "reasoning_effort" => "medium"
               },
               %{
                 "name" => "Default",
                 "mode" => "default",
                 "model" => nil,
                 "reasoning_effort" => nil
               }
             ]
           }

    for {method, params} <- [
          {"externalAgentConfig/detect", %{"includeHome" => "invalid"}},
          {"externalAgentConfig/detect", %{"maxSessions" => -1}},
          {"externalAgentConfig/import", %{}},
          {"externalAgentConfig/import",
           %{
             "migrationItems" => [
               %{
                 "itemType" => "UNKNOWN_SYNTHETIC",
                 "description" => "Invalid",
                 "cwd" => ctx.fixture.workspace
               }
             ]
           }},
          {"externalAgentConfig/import/recordHistory", %{"itemTypeResults" => []}},
          {"externalAgentConfig/import/recordHistory",
           %{"providerId" => "invalid", "itemTypeResults" => "invalid"}},
          {"externalAgentConfig/import/readHistories", ["invalid"]},
          {"hooks/list", %{"cwds" => 42}}
        ] do
      assert upstream_error(pid, method, params)["code"] == -32_600
    end

    memory =
      Map.put(item("MEMORY", ctx.fixture.workspace), "details", %{"memory" => ["owned-only"]})

    error = upstream_error(pid, "externalAgentConfig/import", %{"migrationItems" => [memory]})
    assert error["code"] == -32_600
    assert error["message"] == "external agent memory import is disabled"

    refute File.exists?(
             Path.join(ctx.fixture.codex_home, "memories/extensions/external_agent_import")
           )

    assert_idle(ctx, pid)
  end

  defp start(ctx, capability \\ true) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: ctx.binary,
             args:
               SamgitaCodexDriver.NativeLaunchFixture.ordinary_args([
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: fixture.workspace,
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "RUST_LOG" => "off",
               "NO_COLOR" => "1"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)
    capabilities = if capability == :absent, do: %{}, else: %{"experimentalApi" => capability}

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_import_fixture", "version" => "0.1.0"},
               capabilities
             )

    pid
  end

  defp call(pid, method, params), do: TurnFixture.call(pid, method, params)

  defp upstream_error(pid, method, params),
    do: TurnFixture.upstream_error(pid, method, params, validation: :wire)

  defp histories(pid), do: call(pid, "externalAgentConfig/import/readHistories", nil)

  defp history(pid, id),
    do:
      Enum.find(histories(pid)["data"], &(&1["importId"] == id)) ||
        flunk("Missing completed import #{id}")

  defp config_path(ctx), do: Path.join(ctx.fixture.codex_home, "config.toml")

  defp append_config(ctx, body),
    do: File.write!(config_path(ctx), File.read!(config_path(ctx)) <> "\n" <> body)

  defp item(type, cwd),
    do: %{
      "itemType" => type,
      "description" => "Owned synthetic #{type}",
      "cwd" => cwd,
      "details" => nil
    }

  defp success(type, cwd, source, target, title \\ nil),
    do: %{
      "itemType" => type,
      "cwd" => cwd,
      "source" => source,
      "target" => target,
      "title" => title
    }

  defp repository(ctx, name) do
    root = Path.join(ctx.fixture.workspace, name)
    File.mkdir_p!(Path.join(root, ".git"))
    root
  end

  defp put(ctx, path, body) do
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.root) <> "/")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, body)
  end

  defp assert_uuid(value) do
    assert is_binary(value) and
             value =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
  end

  defp run_import(pid, items, options \\ %{}) do
    result =
      call(pid, "externalAgentConfig/import", Map.merge(%{"migrationItems" => items}, options))

    assert %{"importId" => id} = result
    assert_uuid(id)
    events = completed(pid, id)

    notification =
      TurnFixture.notification(
        events,
        "externalAgentConfig/import/completed",
        &(&1["importId"] == id)
      )

    results = notification["itemTypeResults"]
    assert progress_results(events, id) == results
    assert history(pid, id)["successes"] == Enum.flat_map(results, & &1["successes"])
    assert history(pid, id)["failures"] == Enum.flat_map(results, & &1["failures"])
    {id, results, events}
  end

  defp progress_results(events, id) do
    order =
      ~w(CONFIG SKILLS AGENTS_MD PLUGINS MCP_SERVER_CONFIG SUBAGENTS HOOKS COMMANDS SESSIONS MEMORY)

    events
    |> progress_updates(id)
    |> Enum.group_by(& &1["itemType"])
    |> Enum.map(fn {type, updates} ->
      %{
        "itemType" => type,
        "successes" => Enum.flat_map(updates, & &1["successes"]),
        "failures" => Enum.flat_map(updates, & &1["failures"])
      }
    end)
    |> Enum.sort_by(&Enum.find_index(order, fn type -> type == &1["itemType"] end))
  end

  defp progress_updates(events, id) do
    events
    |> Enum.filter(
      &(&1.wire["method"] == "externalAgentConfig/import/progress" and
          &1.wire["params"]["importId"] == id)
    )
    |> Enum.flat_map(& &1.wire["params"]["itemTypeResults"])
  end

  defp completed(pid, id, events \\ [], deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 10_000
    assert {:ok, batch} = Session.drain(pid)
    events = events ++ batch

    if TurnFixture.notification(
         events,
         "externalAgentConfig/import/completed",
         &(&1["importId"] == id)
       ) do
      events
    else
      assert System.monotonic_time(:millisecond) < deadline,
             "Native import completion deadline: #{inspect(events)}"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected import event gap")
      after
        20 -> :ok
      end

      completed(pid, id, events, deadline)
    end
  end

  defp assert_idle(ctx, pid) do
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
    assert ModelFixture.requests(ctx.fixture) == []
  end
end
