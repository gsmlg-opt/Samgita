defmodule SamgitaCodexDriver.AdditionalMethodFamiliesTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-codex-additional-#{System.unique_integer([:positive])}"
      )

    fixture = ModelFixture.start(root, Map.get(tags, :scenario, "assistant"))

    on_exit(fn ->
      ModelFixture.close(fixture)
      File.rm_rf!(root)
    end)

    %{binary: binary, fixture: fixture}
  end

  defp start(context, config \\ "") do
    path = Path.join(context.fixture.codex_home, "config.toml")
    File.write!(path, File.read!(path) <> "\n" <> config)

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: context.binary,
             args: ["app-server", "--listen", "stdio://"],
             cwd: context.fixture.workspace,
             env: %{
               "HOME" => context.fixture.home,
               "CODEX_HOME" => context.fixture.codex_home,
               "PATH" => context.fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "RUST_LOG" => "off"
             }
           ]}
      )

    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_additional_families", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp call(pid, method, params \\ %{}) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp upstream_error(pid, method, params) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             Session.request(pid, method, params)

    assert is_integer(error["code"]) and error["code"] < 0
    error
  end

  defp events_until(pid, predicate, acc \\ [], deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 15_000
    assert {:ok, events} = Session.drain(pid)
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
    Enum.find_value(events, fn e ->
      if e.wire["method"] == method and predicate.(e.wire["params"]), do: e.wire["params"]
    end)
  end

  defp thread(pid, fixture, extra \\ %{}) do
    call(
      pid,
      "thread/start",
      Map.merge(
        %{
          "cwd" => fixture.workspace,
          "model" => "mock-model",
          "modelProvider" => "fixture",
          "sandbox" => "read-only",
          "approvalPolicy" => "on-request",
          "ephemeral" => false
        },
        extra
      )
    )["thread"]["id"]
  end

  defp start_turn(pid, id, text) do
    call(pid, "turn/start", %{"threadId" => id, "input" => [%{"type" => "text", "text" => text}]})[
      "turn"
    ]["id"]
  end

  defp completed(pid, id, turn) do
    events =
      events_until(pid, &notification(&1, "turn/completed", fn p -> p["turn"]["id"] == turn end))

    assert %{"threadId" => ^id, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed")

    refute Enum.any?(events, &(&1.kind == :server_request))
    events
  end

  test "legacy fuzzy search matches real paths and connection search sessions update and stop",
       context do
    pid = start(context)
    path = Path.join(context.fixture.workspace, "src/synthetic_needle.ex")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "synthetic file contents")
    File.write!(Path.join(context.fixture.workspace, "other.txt"), "other")

    result =
      call(pid, "fuzzyFileSearch", %{
        "roots" => [context.fixture.workspace],
        "query" => "synthetic_needle",
        "cancellationToken" => "fixture-search"
      })

    assert [
             %{
               "file_name" => "synthetic_needle.ex",
               "path" => "src/synthetic_needle.ex",
               "root" => root,
               "match_type" => "file"
             }
           ] = result["files"]

    assert root == context.fixture.workspace

    assert call(pid, "fuzzyFileSearch/sessionStart", %{
             "sessionId" => "fixture-search-session",
             "roots" => [root]
           }) == %{}

    assert call(pid, "fuzzyFileSearch/sessionUpdate", %{
             "sessionId" => "fixture-search-session",
             "query" => "synthetic_needle"
           }) == %{}

    events =
      events_until(
        pid,
        &notification(&1, "fuzzyFileSearch/sessionUpdated", fn p ->
          p["sessionId"] == "fixture-search-session" and p["query"] == "synthetic_needle" and
            p["files"] != []
        end)
      )

    update = notification(events, "fuzzyFileSearch/sessionUpdated", &(&1["files"] != []))
    assert Enum.any?(update["files"], &(&1["file_name"] == "synthetic_needle.ex"))

    assert call(pid, "fuzzyFileSearch/sessionStop", %{"sessionId" => "fixture-search-session"}) ==
             %{}

    error =
      upstream_error(pid, "fuzzyFileSearch/sessionUpdate", %{
        "sessionId" => "fixture-search-session",
        "query" => "other"
      })

    assert error["message"] == "fuzzy file search session not found: fixture-search-session"
  end

  test "inline review delivers native review items and a completed review turn", context do
    pid = start(context)
    id = thread(pid, context.fixture)

    review =
      call(pid, "review/start", %{
        "threadId" => id,
        "delivery" => "inline",
        "target" => %{"type" => "custom", "instructions" => "Review synthetic fixture only"}
      })

    assert review["reviewThreadId"] == id
    events = completed(pid, id, review["turn"]["id"])
    entered = notification(events, "item/started", &(&1["item"]["type"] == "enteredReviewMode"))
    assert entered["item"]["review"] == "Review synthetic fixture only"
    exited = notification(events, "item/completed", &(&1["item"]["type"] == "exitedReviewMode"))
    assert exited["threadId"] == id
    assert exited["turnId"] == review["turn"]["id"]
    assert exited["item"]["review"] =~ "Deterministic local fixture answer"

    assert JSON.encode!(hd(ModelFixture.requests(context.fixture))) =~
             "Review synthetic fixture only"
  end

  test "legacy summary supports persisted thread IDs and rollout paths without leaking auth",
       context do
    pid = start(context)
    id = thread(pid, context.fixture, %{"historyMode" => "legacy"})
    turn = start_turn(pid, id, "Synthetic legacy conversation summary")
    completed(pid, id, turn)
    by_id = call(pid, "getConversationSummary", %{"conversationId" => id})["summary"]
    assert by_id["conversationId"] == id
    assert by_id["cwd"] == context.fixture.workspace
    assert by_id["preview"] == "Synthetic legacy conversation summary"
    assert File.regular?(by_id["path"])
    by_path = call(pid, "getConversationSummary", %{"rolloutPath" => by_id["path"]})["summary"]
    assert by_path == by_id

    assert %{"authMethod" => nil, "authToken" => nil, "requiresOpenaiAuth" => false} =
             call(pid, "getAuthStatus", %{"includeToken" => true, "refreshToken" => false})

    error = upstream_error(pid, "gitDiffToRemote", %{"cwd" => context.fixture.workspace})
    assert error["message"] =~ "git"
  end

  test "thread settings preserve omitted and null plugin lists while explicit empty clears",
       context do
    pid = start(context)
    id = thread(pid, context.fixture)

    for {extra, expected} <- [
          {%{"disabledPluginIds" => ["synthetic@local"], "serviceTier" => "priority"},
           ["synthetic@local"]},
          {%{"disabledPluginIds" => nil, "effort" => "medium"}, ["synthetic@local"]},
          {%{"serviceTier" => nil}, ["synthetic@local"]},
          {%{"disabledPluginIds" => []}, []}
        ] do
      assert call(pid, "thread/settings/update", Map.put(extra, "threadId", id)) == %{}

      events =
        events_until(
          pid,
          &notification(&1, "thread/settings/updated", fn p -> p["threadId"] == id end)
        )

      settings = notification(events, "thread/settings/updated")["threadSettings"]
      assert settings["disabledPluginIds"] == expected

      # Upstream represents an explicitly cleared tier by its default sentinel.
      if Map.has_key?(extra, "serviceTier"),
        do: assert(settings["serviceTier"] == (extra["serviceTier"] || "default"))
    end

    refute File.exists?(context.fixture.requests)
    turn = start_turn(pid, id, "Use explicit fixture settings")
    completed(pid, id, turn)
    body = hd(ModelFixture.requests(context.fixture))
    assert body["model"] == "mock-model"
    assert body["reasoning"]["effort"] == "medium"
    assert body["service_tier"] == nil
  end

  test "turn settings distinguish disabled switching from an expired live target", context do
    pid = start(context)
    id = thread(pid, context.fixture)
    turn = start_turn(pid, id, "Synthetic closed turn")
    completed(pid, id, turn)

    error =
      upstream_error(pid, "turn/settings/update", %{
        "threadId" => id,
        "turnId" => turn,
        "model" => "mock-model"
      })

    assert error["message"] == "turn settings updates require the step_model_switching feature"

    # This is a known feature, but the pinned runtime-override allowlist excludes it.
    assert call(pid, "experimentalFeature/enablement/set", %{
             "enablement" => %{"step_model_switching" => true}
           }) == %{"enablement" => %{}}

    assert upstream_error(pid, "turn/settings/update", %{
             "threadId" => id,
             "turnId" => turn,
             "model" => "mock-model"
           })["message"] ==
             "turn settings updates require the step_model_switching feature"

    assert :ok = Session.close(pid)
    enabled = start(context, "[features]\nstep_model_switching = true\n")
    assert call(enabled, "thread/resume", %{"threadId" => id})["thread"]["id"] == id

    assert call(enabled, "turn/settings/update", %{
             "threadId" => id,
             "turnId" => turn,
             "model" => "mock-model"
           }) == %{"status" => "targetUnavailable"}

    assert length(ModelFixture.requests(context.fixture)) == 1
  end

  test "native injected history is visible to the next local model request", context do
    pid = start(context)
    id = thread(pid, context.fixture)

    item = %{
      "type" => "message",
      "role" => "assistant",
      "content" => [%{"type" => "output_text", "text" => "Synthetic injected context"}]
    }

    assert call(pid, "thread/inject_items", %{"threadId" => id, "items" => [item]}) == %{}
    turn = start_turn(pid, id, "Use only synthetic injected context")
    completed(pid, id, turn)
    input = hd(ModelFixture.requests(context.fixture))["input"]
    injected = Enum.find(input, &(Map.drop(&1, ["id"]) == item))
    assert is_binary(injected["id"])
    assert length(ModelFixture.requests(context.fixture)) == 1
  end

  test "sections retain stable identities through rename, thread movement and deletion",
       context do
    pid = start(context)
    id = thread(pid, context.fixture)
    turn = start_turn(pid, id, "Synthetic section membership")
    completed(pid, id, turn)

    section =
      call(pid, "threadSection/create", %{
        "name" => "  Fixture section  ",
        "appearance" => %{"icon" => "folder", "color" => "purple"}
      })["section"]

    assert section["name"] == "Fixture section"
    section_id = section["id"]
    assert Enum.any?(call(pid, "threadSection/list")["data"], &(&1["id"] == section_id))

    renamed =
      call(pid, "threadSection/update", %{
        "sectionId" => section_id,
        "name" => "Renamed fixture",
        "appearance" => nil
      })["section"]

    assert renamed["id"] == section_id
    assert renamed["appearance"] == nil
    assert call(pid, "thread/section/move", %{"threadId" => id, "sectionId" => section_id}) == %{}
    assert call(pid, "thread/read", %{"threadId" => id})["thread"]["section"]["id"] == section_id
    assert [%{"id" => ^id}] = call(pid, "thread/list", %{"sectionId" => section_id})["data"]
    assert call(pid, "threadSection/delete", %{"sectionId" => section_id}) == %{}
    assert call(pid, "thread/read", %{"threadId" => id})["thread"]["section"] == nil
    refute Enum.any?(call(pid, "threadSection/list")["data"], &(&1["id"] == section_id))

    assert upstream_error(pid, "threadSection/update", %{
             "sectionId" => section_id,
             "name" => "stale"
           })["message"] =~ "section"
  end

  @tag scenario: "command"
  test "queued messages preserve identity and order while execution is blocked on an explicit decision",
       context do
    pid = start(context)
    id = thread(pid, context.fixture)
    turn = start_turn(pid, id, "Synthetic held approval for queue checks")
    events = events_until(pid, &Enum.any?(&1, fn e -> e.kind == :server_request end))
    approval = Enum.find(events, &(&1.kind == :server_request))
    assert approval.wire["method"] == "item/commandExecution/requestApproval"
    assert approval.wire["params"]["threadId"] == id
    assert approval.wire["params"]["turnId"] == turn
    input = fn text -> [%{"type" => "text", "text" => text}] end

    first =
      call(pid, "thread/queue/add", %{
        "threadId" => id,
        "clientUserMessageId" => "fixture-first",
        "input" => input.("first")
      })["queuedSubmission"]

    second =
      call(pid, "thread/queue/add", %{
        "threadId" => id,
        "clientUserMessageId" => "fixture-second",
        "input" => input.("second")
      })["queuedSubmission"]

    page = call(pid, "thread/queue/list", %{"threadId" => id, "limit" => 1})
    assert [first] == page["data"]

    assert [second] ==
             call(pid, "thread/queue/list", %{
               "threadId" => id,
               "cursor" => page["nextCursor"],
               "limit" => 1
             })["data"]

    updated =
      call(pid, "thread/queue/update", %{
        "threadId" => id,
        "queuedSubmissionId" => first["id"],
        "input" => input.("edited")
      })["queuedSubmission"]

    assert updated["id"] == first["id"]
    assert updated["clientUserMessageId"] == first["clientUserMessageId"]
    assert hd(updated["input"])["text"] == "edited"

    error =
      upstream_error(pid, "thread/queue/reorder", %{
        "threadId" => id,
        "queuedSubmissionIds" => [first["id"]]
      })

    assert error["message"] == "queue reorder must include every queued submission exactly once"

    assert call(pid, "thread/queue/reorder", %{
             "threadId" => id,
             "queuedSubmissionIds" => [second["id"], first["id"]]
           }) == %{}

    assert Enum.map(call(pid, "thread/queue/list", %{"threadId" => id})["data"], & &1["id"]) == [
             second["id"],
             first["id"]
           ]

    assert upstream_error(pid, "thread/queue/start", %{
             "threadId" => id,
             "queuedSubmissionId" => first["id"]
           })["message"] =~ "active"

    for queued <- [first, second] do
      assert call(pid, "thread/queue/delete", %{
               "threadId" => id,
               "queuedSubmissionId" => queued["id"]
             }) == %{"deleted" => true}
    end

    assert call(pid, "thread/queue/list", %{"threadId" => id})["data"] == []
    assert :ok = Session.respond(pid, approval.handle, {:ok, %{"decision" => "decline"}})
    completed(pid, id, turn)
    assert length(ModelFixture.requests(context.fixture)) == 2

    assert upstream_error(pid, "thread/queue/start", %{"threadId" => id})["message"] ==
             "queue is empty"
  end

  test "attachment source identity deduplicates and owners remain queryable until removal",
       context do
    pid = start(context)
    id = thread(pid, context.fixture)
    turn = start_turn(pid, id, "Synthetic attachment persistence")
    completed(pid, id, turn)

    params = %{
      "threadId" => id,
      "attachmentType" => "document",
      "identityKey" => "synthetic-document",
      "payload" => %{"fixture" => true, "nested" => [1, nil]}
    }

    added = call(pid, "thread/attachment/add", params)
    assert added["outcome"] == "created"
    assert added["attachment"]["payload"] == params["payload"]
    duplicate = call(pid, "thread/attachment/add", params)
    assert duplicate["outcome"] == "existing"
    assert duplicate["attachment"] == added["attachment"]

    assert [added["attachment"]] ==
             call(pid, "thread/attachment/list", %{"threadId" => id})["data"]

    owners =
      call(
        pid,
        "thread/attachmentOwner/list",
        Map.take(params, ["attachmentType", "identityKey"])
      )["data"]

    assert Enum.any?(owners, &(&1["threadId"] == id and &1["archived"] == false))
    assert call(pid, "thread/attachment/remove", Map.delete(params, "payload")) == %{}
    assert call(pid, "thread/attachment/list", %{"threadId" => id})["data"] == []
  end

  test "durable read-state revisions reject stale updates without erasing the unread marker",
       context do
    pid = start(context)
    id = thread(pid, context.fixture)
    turn = start_turn(pid, id, "Synthetic read receipt")
    completed(pid, id, turn)
    original = call(pid, "thread/read", %{"threadId" => id})["readState"]
    assert is_binary(original["revision"])

    marked =
      call(pid, "thread/readState/update", %{
        "threadId" => id,
        "expectedRevision" => original["revision"],
        "operation" => %{"type" => "unread"}
      })["readState"]

    assert marked["firstUnread"] != nil

    error =
      upstream_error(pid, "thread/readState/update", %{
        "threadId" => id,
        "expectedRevision" => original["revision"],
        "operation" => %{"type" => "read"}
      })

    assert error["data"]["reason"] == "readStateConflict"
    assert error["data"]["readState"] == marked
    assert call(pid, "thread/read", %{"threadId" => id})["readState"] == marked

    read =
      call(pid, "thread/readState/update", %{
        "threadId" => id,
        "expectedRevision" => marked["revision"],
        "operation" => %{"type" => "read"}
      })["readState"]

    assert read["firstUnread"] == nil
  end

  test "runtime feature overrides and local discovery expose metadata without modifying config",
       context do
    pid = start(context)
    config = Path.join(context.fixture.codex_home, "config.toml") |> File.read!()
    first = call(pid, "experimentalFeature/list", %{"limit" => 1})
    assert length(first["data"]) == 1
    assert is_binary(first["nextCursor"])
    next = call(pid, "experimentalFeature/list", %{"limit" => 1, "cursor" => first["nextCursor"]})
    refute hd(first["data"])["name"] == hd(next["data"])["name"]

    assert call(pid, "experimentalFeature/enablement/set", %{
             "enablement" => %{"auth_elicitation" => true}
           }) == %{"enablement" => %{"auth_elicitation" => true}}

    assert call(pid, "config/read", %{"includeLayers" => false})["config"]["features"][
             "auth_elicitation"
           ]

    assert File.read!(Path.join(context.fixture.codex_home, "config.toml")) == config

    assert call(pid, "experimentalFeature/enablement/set", %{"enablement" => %{}}) == %{
             "enablement" => %{}
           }

    profiles = call(pid, "permissionProfile/list", %{"cwd" => context.fixture.workspace})["data"]
    assert Enum.any?(profiles, &(&1["id"] == ":read-only" and &1["allowed"]))
    modes = call(pid, "collaborationMode/list")["data"]
    assert Enum.any?(modes, &(&1["mode"] == "plan"))

    assert [%{"cwd" => cwd, "hooks" => [], "errors" => []}] =
             call(pid, "hooks/list", %{"cwds" => [context.fixture.workspace]})["data"]

    assert cwd == context.fixture.workspace
  end

  test "external import discovery and history stay local and retain provider identity", context do
    pid = start(context)

    assert %{"items" => [], "connectors" => []} =
             call(pid, "externalAgentConfig/detect", %{
               "cwds" => [context.fixture.workspace],
               "includeHome" => false,
               "maxSessions" => 1
             })

    assert call(pid, "externalAgentConfig/import/readHistories", nil)["data"] == []

    recorded =
      call(pid, "externalAgentConfig/import/recordHistory", %{
        "providerId" => "synthetic-provider",
        "itemTypeResults" => []
      })

    assert is_binary(recorded["importId"])
    histories = call(pid, "externalAgentConfig/import/readHistories", nil)["data"]

    assert Enum.any?(
             histories,
             &(&1["importId"] == recorded["importId"] and &1["providerId"] == "synthetic-provider")
           )

    refute File.exists?(context.fixture.requests)
  end

  test "local plugin discovery, read, install and uninstall use explicit synthetic marketplace",
       context do
    workspace = context.fixture.workspace
    marketplace = Path.join(workspace, ".agents/plugins/marketplace.json")
    plugin = Path.join(workspace, "fixture-plugin")
    File.mkdir_p!(Path.join(workspace, ".git"))
    File.mkdir_p!(Path.dirname(marketplace))
    File.mkdir_p!(Path.join(plugin, ".codex-plugin"))

    File.write!(
      marketplace,
      JSON.encode!(%{
        "name" => "fixture-market",
        "plugins" => [
          %{
            "name" => "fixture-plugin",
            "source" => %{"source" => "local", "path" => "./fixture-plugin"}
          }
        ]
      })
    )

    File.write!(
      Path.join(plugin, ".codex-plugin/plugin.json"),
      JSON.encode!(%{"name" => "fixture-plugin", "description" => "Synthetic local plugin"})
    )

    pid = start(context, "[features]\nplugins = true\nremote_plugin = false\n")

    listing =
      call(pid, "plugin/list", %{
        "cwds" => [workspace],
        "marketplaceKinds" => ["local"],
        "forceRefetch" => false
      })

    assert listing["marketplaceLoadErrors"] == []
    market = Enum.find(listing["marketplaces"], &(&1["name"] == "fixture-market"))
    assert market
    params = %{"marketplacePath" => marketplace, "pluginName" => "fixture-plugin"}
    detail = call(pid, "plugin/read", params)["plugin"]
    assert detail["summary"]["name"] == "fixture-plugin"
    refute detail["summary"]["installed"]
    assert detail["description"] == "Synthetic local plugin"

    installed =
      call(pid, "plugin/install", Map.put(params, "installAttemptId", "synthetic-install"))

    assert installed["appsNeedingAuth"] == []
    detail = call(pid, "plugin/read", params)["plugin"]
    assert detail["summary"]["installed"]
    assert call(pid, "plugin/uninstall", %{"pluginId" => detail["summary"]["id"]}) == %{}
    refute call(pid, "plugin/read", params)["plugin"]["summary"]["installed"]

    error =
      upstream_error(pid, "plugin/read", Map.put(params, "pluginName", "missing-fixture-plugin"))

    assert error["message"] =~ "missing-fixture-plugin"
    refute File.exists?(context.fixture.requests)
  end
end
