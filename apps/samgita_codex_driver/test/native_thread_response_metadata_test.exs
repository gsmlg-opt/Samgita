defmodule SamgitaCodexDriver.NativeThreadResponseMetadataTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  import TurnFixture, only: [call: 3, upstream_error: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @instructions "Owned metadata-only project instructions. No execution requested.\n"
  @disabled ["unused-owned@metadata-fixture"]
  @readonly %{"type" => "readOnly", "networkAccess" => false}
  @collaboration %{
    "mode" => "plan",
    "settings" => %{
      "model" => "mock-model",
      "reasoning_effort" => nil,
      "developer_instructions" => "Owned metadata-only collaboration instructions."
    }
  }

  setup tags do
    ctx = TurnFixture.setup(tags)

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    TurnFixture.configure_model(ctx, %{})
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      "cli_auth_credentials_store = \"ephemeral\"\n" <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    config_bytes = File.read!(config)
    on_exit(fn -> assert File.read!(config) == config_bytes end)
    extra = Path.join(ctx.root, "owned-extra-workspace")
    File.mkdir!(extra)
    source = Path.join(ctx.fixture.workspace, "AGENTS.md")
    File.write!(source, @instructions)
    ctx |> Map.put(:extra, extra) |> Map.put(:source, source)
  end

  test "loaded resume reports applied plugin collaboration roots and cached instruction metadata",
       ctx do
    pid = TurnFixture.start(ctx)
    {id, path} = parent(ctx, pid)
    apply_settings(ctx, pid, id)
    bytes = File.read!(path)

    # Loaded instructions are session state: disk disappearance must not turn
    # the diagnostic source list into a fresh filesystem discovery result.
    parked = Path.join(ctx.root, "owned-parked-AGENTS.md")
    File.rename!(ctx.source, parked)

    response = call(pid, "thread/resume", %{"threadId" => id, "excludeTurns" => true})
    assert Map.fetch!(response["thread"], "id") == id
    assert Map.fetch!(response["thread"], "turns") == []
    assert_metadata(ctx, response, @disabled)
    assert Map.fetch!(response, "collaborationMode") === @collaboration
    assert Map.fetch!(response, "initialTurnsPage") == nil
    assert File.read!(path) == bytes
    assert File.read!(parked) == @instructions
    File.rename!(parked, ctx.source)
    assert_no_dispatch(ctx, pid)
    assert :ok = Session.close(pid)
  end

  test "cold resume explicit owned roots exposes independently expected source and sandbox metadata",
       ctx do
    first = TurnFixture.start(ctx)
    {id, _path} = parent(ctx, first)
    assert_no_dispatch(ctx, first)
    assert :ok = Session.close(first)

    cold = TurnFixture.start(ctx)
    assert call(cold, "thread/loaded/list", %{})["data"] == []

    response =
      call(cold, "thread/resume", %{
        "threadId" => id,
        "runtimeWorkspaceRoots" => roots(ctx),
        "permissions" => ":read-only",
        "excludeTurns" => true
      })

    assert Map.fetch!(response["thread"], "id") == id
    assert Map.fetch!(response["thread"], "turns") == []
    assert_metadata(ctx, response, [])
    assert File.read!(ctx.source) == @instructions
    assert_no_dispatch(ctx, cold)
    assert :ok = Session.close(cold)
  end

  test "ordinary and prediction forks expose their own exact metadata without starting work",
       ctx do
    pid = TurnFixture.start(ctx)
    {id, path} = parent(ctx, pid)

    ordinary =
      call(pid, "thread/fork", %{
        "threadId" => id,
        "runtimeWorkspaceRoots" => roots(ctx),
        "permissions" => ":read-only",
        "excludeTurns" => true
      })

    assert_metadata(ctx, ordinary, [])
    assert_child(ordinary, id)
    assert ordinary["thread"]["ephemeral"] == false
    assert File.regular?(ordinary["thread"]["path"])
    assert_no_dispatch(ctx, pid)

    apply_settings(ctx, pid, id)
    before = call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]
    bytes = File.read!(path)

    prediction_params = %{
      "threadId" => id,
      "experimentalPredictionMode" => true,
      "excludeTurns" => true
    }

    assert upstream_error(pid, "thread/fork", prediction_params) == %{
             "code" => -32_600,
             "message" => "`experimentalPredictionMode` requires `ephemeral: true`"
           }

    assert call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"] ==
             before

    assert File.read!(path) == bytes
    assert_no_dispatch(ctx, pid)
    prediction = call(pid, "thread/fork", Map.put(prediction_params, "ephemeral", true))

    assert_metadata(ctx, prediction, @disabled)
    assert_child(prediction, id)
    assert Map.fetch!(prediction["thread"], "ephemeral") == true
    assert Map.fetch!(prediction["thread"], "path") == nil
    refute prediction["thread"]["id"] == ordinary["thread"]["id"]

    assert call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"] ==
             before

    assert File.read!(path) == bytes
    assert File.read!(ctx.source) == @instructions
    assert_no_dispatch(ctx, pid)
    assert :ok = Session.close(pid)
  end

  for mode <- ["legacy", "paginated"] do
    @prediction_history_mode mode
    test "#{mode} prediction continuation inherits live instructions and tools with isolated histories",
         ctx do
      pid = TurnFixture.start(ctx)
      source_contract = prediction_contract(:source)
      sibling_contract = prediction_contract(:sibling)
      source = prediction_thread(ctx, pid, source_contract, @prediction_history_mode)
      sibling = prediction_thread(ctx, pid, sibling_contract, @prediction_history_mode)
      prediction_settings(pid, source, source_contract)
      prediction_settings(pid, sibling, sibling_contract)
      assert_no_dispatch(ctx, pid)

      first_text = "Owned prediction source prefix λ"
      child_text = "Owned prediction child-only continuation 🙂"
      source_text = "Owned prediction source-only continuation λ"
      sibling_text = "Owned prediction sibling-only continuation 🙂"
      child_next = "Owned prediction child second continuation λ🙂"
      all_texts = [first_text, child_text, source_text, sibling_text, child_next]

      first = prediction_complete(ctx, pid, source, first_text, 1)
      [initial_request] = ModelFixture.requests(ctx.fixture)

      assert_prediction_request(
        initial_request,
        source_contract,
        sibling_contract,
        [first_text],
        all_texts -- [first_text],
        0
      )

      source_before = prediction_read(pid, source)
      sibling_before = prediction_read(pid, sibling)
      source_bytes = File.read!(source_before["path"])
      sibling_bytes = File.read!(sibling_before["path"])
      assert Enum.map(source_before["turns"], & &1["id"]) == [first]
      assert sibling_before["turns"] == []

      prediction =
        call(pid, "thread/fork", %{
          "threadId" => source,
          "experimentalPredictionMode" => true,
          "ephemeral" => true,
          "excludeTurns" => true
        })

      assert_child(prediction, source)
      assert_metadata(ctx, prediction, source_contract.disabled)
      assert prediction["model"] == "mock-model"
      assert prediction["modelProvider"] == "fixture"
      # The pinned ThreadForkResponse omits collaborationMode. Inheritance is
      # proved below against the child's actual provider instructions and tools.
      refute Map.has_key?(prediction, "collaborationMode")
      assert prediction["thread"]["ephemeral"] == true
      assert Map.fetch!(prediction["thread"], "path") == nil
      child = prediction["thread"]["id"]
      refute child == sibling
      assert prediction_read(pid, source) == source_before
      assert prediction_read(pid, sibling) == sibling_before
      assert File.read!(source_before["path"]) == source_bytes
      assert File.read!(sibling_before["path"]) == sibling_bytes
      assert_prediction_idle(ctx, pid, 1)

      prediction_complete(ctx, pid, child, child_text, 2)
      child_request = Enum.at(ModelFixture.requests(ctx.fixture), 1)

      assert_prediction_request(
        child_request,
        source_contract,
        sibling_contract,
        [first_text, child_text],
        [source_text, sibling_text, child_next],
        1
      )

      assert prediction_read(pid, source) == source_before
      assert prediction_read(pid, sibling) == sibling_before
      assert File.read!(source_before["path"]) == source_bytes
      assert File.read!(sibling_before["path"]) == sibling_bytes

      source_next = prediction_complete(ctx, pid, source, source_text, 3)
      source_request = Enum.at(ModelFixture.requests(ctx.fixture), 2)

      assert_prediction_request(
        source_request,
        source_contract,
        sibling_contract,
        [first_text, source_text],
        [child_text, sibling_text, child_next],
        1
      )

      source_after_parent = prediction_read(pid, source)
      source_after_parent_bytes = File.read!(source_after_parent["path"])
      assert prediction_read(pid, sibling) == sibling_before
      assert File.read!(sibling_before["path"]) == sibling_bytes

      sibling_turn = prediction_complete(ctx, pid, sibling, sibling_text, 4)
      sibling_request = Enum.at(ModelFixture.requests(ctx.fixture), 3)

      assert_prediction_request(
        sibling_request,
        sibling_contract,
        source_contract,
        [sibling_text],
        [first_text, child_text, source_text, child_next],
        0
      )

      assert prediction_read(pid, source) == source_after_parent
      assert File.read!(source_after_parent["path"]) == source_after_parent_bytes
      source_after = prediction_read(pid, source)
      sibling_after = prediction_read(pid, sibling)
      assert Enum.map(source_after["turns"], & &1["id"]) == [first, source_next]
      assert Enum.map(sibling_after["turns"], & &1["id"]) == [sibling_turn]
      source_after_bytes = File.read!(source_after["path"])
      sibling_after_bytes = File.read!(sibling_after["path"])

      prediction_complete(ctx, pid, child, child_next, 5)
      child_next_request = Enum.at(ModelFixture.requests(ctx.fixture), 4)

      assert_prediction_request(
        child_next_request,
        source_contract,
        sibling_contract,
        [first_text, child_text, child_next],
        [source_text, sibling_text],
        2
      )

      assert prediction_read(pid, source) == source_after
      assert prediction_read(pid, sibling) == sibling_after
      assert File.read!(source_after["path"]) == source_after_bytes
      assert File.read!(sibling_after["path"]) == sibling_after_bytes
      assert_prediction_ephemeral(ctx, pid, child)
      assert File.read!(ctx.source) == @instructions
      assert_prediction_idle(ctx, pid, 5)
      assert :ok = Session.close(pid)

      cold = TurnFixture.start(ctx)
      assert call(cold, "thread/loaded/list", %{})["data"] == []

      assert upstream_error(cold, "thread/read", %{
               "threadId" => child,
               "includeTurns" => false
             }) == %{"code" => -32_600, "message" => "thread not loaded: #{child}"}

      assert upstream_error(cold, "thread/resume", %{
               "threadId" => child,
               "excludeTurns" => true
             }) == %{"code" => -32_600, "message" => "no rollout found for thread id #{child}"}

      assert Enum.map(prediction_read(cold, source)["turns"], & &1["id"]) ==
               [first, source_next]

      assert Enum.map(prediction_read(cold, sibling)["turns"], & &1["id"]) == [sibling_turn]
      assert File.read!(source_after["path"]) == source_after_bytes
      assert File.read!(sibling_after["path"]) == sibling_after_bytes
      assert call(cold, "thread/loaded/list", %{})["data"] == []
      assert_prediction_idle(ctx, cold, 5)
      assert :ok = Session.close(cold)
    end
  end

  defp prediction_contract(owner) do
    %{
      base: "Owned prediction #{owner} base instructions.",
      developer: "Owned prediction #{owner} developer policy.",
      disabled: ["unused-owned-#{owner}@prediction-fixture"],
      collaboration: %{
        "mode" => "plan",
        "settings" => %{
          "model" => "mock-model",
          "reasoning_effort" => nil,
          "developer_instructions" => "Owned prediction #{owner} collaboration instructions."
        }
      },
      tool: %{
        "type" => "function",
        "name" => "owned_prediction_#{owner}",
        "description" => "Owned prediction #{owner} metadata-only tool.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{"marker" => %{"type" => "string"}},
          "required" => ["marker"],
          "additionalProperties" => false
        }
      }
    }
  end

  defp prediction_thread(ctx, pid, contract, mode) do
    id =
      TurnFixture.thread(ctx, pid, %{
        "historyMode" => mode,
        "runtimeWorkspaceRoots" => roots(ctx),
        "baseInstructions" => contract.base,
        "developerInstructions" => contract.developer,
        "dynamicTools" => [contract.tool]
      })

    assert call(pid, "thread/name/set", %{"threadId" => id, "name" => contract.base}) == %{}
    assert prediction_read(pid, id)["turns"] == []
    id
  end

  defp prediction_settings(pid, id, contract) do
    assert call(pid, "thread/settings/update", %{
             "threadId" => id,
             "disabledPluginIds" => contract.disabled,
             "collaborationMode" => contract.collaboration
           }) == %{}

    events =
      collect(pid, [], fn events ->
        TurnFixture.notification(events, "thread/settings/updated", fn p ->
          p["threadId"] == id and
            p["threadSettings"]["collaborationMode"] == contract.collaboration
        end) != nil
      end)

    applied =
      TurnFixture.notification(events, "thread/settings/updated", &(&1["threadId"] == id))[
        "threadSettings"
      ]

    assert applied["collaborationMode"] === contract.collaboration
    assert applied["disabledPluginIds"] === contract.disabled

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             event.kind == :server_request or String.starts_with?(method, "turn/") or
               String.starts_with?(method, "item/")
           end)
  end

  defp prediction_complete(ctx, pid, id, text, count) do
    assert length(ModelFixture.requests(ctx.fixture)) == count - 1
    turn = TurnFixture.start_turn(pid, id, [%{"type" => "text", "text" => text}])
    events = TurnFixture.finish_turn(pid, id, turn)

    assert %{
             "threadId" => ^id,
             "turnId" => ^turn,
             "item" => %{
               "type" => "agentMessage",
               "text" => "Deterministic local fixture answer"
             }
           } =
             TurnFixture.notification(events, "item/completed", fn p ->
               p["threadId"] == id and p["turnId"] == turn and
                 p["item"]["type"] == "agentMessage"
             end)

    refute Enum.any?(events, &(&1.kind == :server_request or &1.wire["method"] == "error"))
    assert_prediction_idle(ctx, pid, count)
    turn
  end

  defp assert_prediction_request(request, expected, excluded, present, absent, answers) do
    assert request["model"] == "mock-model"
    refute Map.has_key?(request, "instructions")
    base = expected.base

    assert %{
             "type" => "message",
             "role" => "developer",
             "content" => [%{"type" => "input_text", "text" => ^base}]
           } = hd(request["input"])

    developer =
      request["input"]
      |> Enum.filter(&(&1["role"] == "developer"))
      |> Enum.flat_map(&Map.get(&1, "content", []))

    collaboration =
      "<collaboration_mode>" <>
        expected.collaboration["settings"]["developer_instructions"] <> "</collaboration_mode>"

    for text <- [expected.base, expected.developer, collaboration] do
      assert Enum.count(developer, &(&1 == %{"type" => "input_text", "text" => text})) == 1
    end

    user =
      request["input"]
      |> Enum.filter(&(&1["role"] == "user"))
      |> Enum.flat_map(&Map.get(&1, "content", []))

    for text <- present do
      assert Enum.count(user, &(&1 == %{"type" => "input_text", "text" => text})) == 1
    end

    all_content = Enum.flat_map(request["input"], &Map.get(&1, "content", []))
    all_text = Enum.map_join(all_content, "\n", &Map.get(&1, "text", ""))

    for text <-
          absent ++
            [
              excluded.base,
              excluded.developer,
              excluded.collaboration["settings"]["developer_instructions"]
            ] do
      refute String.contains?(all_text, text)
    end

    assert String.contains?(all_text, String.trim(@instructions))

    assistant =
      request["input"]
      |> Enum.filter(&(&1["role"] == "assistant"))
      |> Enum.flat_map(&Map.get(&1, "content", []))

    assert Enum.count(assistant, fn item ->
             item["type"] == "output_text" and
               item["text"] == "Deterministic local fixture answer"
           end) == answers

    tool = expected.tool

    assert Enum.filter(request["tools"], &(&1["name"] == tool["name"])) == [
             %{
               "type" => "function",
               "name" => tool["name"],
               "description" => tool["description"],
               "strict" => false,
               "parameters" => tool["inputSchema"]
             }
           ]

    refute Enum.any?(request["tools"], &(&1["name"] == excluded.tool["name"]))
  end

  defp prediction_read(pid, id),
    do: call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]

  defp assert_prediction_idle(ctx, pid, count) do
    assert length(ModelFixture.requests(ctx.fixture)) == count
    assert Session.interaction_outcomes(pid) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
  end

  defp assert_prediction_ephemeral(ctx, pid, id) do
    metadata = call(pid, "thread/read", %{"threadId" => id, "includeTurns" => false})["thread"]
    assert metadata["id"] == id and metadata["ephemeral"] == true
    assert Map.fetch!(metadata, "path") == nil
    refute Enum.any?(call(pid, "thread/list", %{"limit" => 100})["data"], &(&1["id"] == id))
    paths = Path.wildcard(Path.join(ctx.fixture.codex_home, "**/rollout-*"), match_dot: true)
    refute Enum.any?(paths, &(File.regular?(&1) and String.contains?(Path.basename(&1), id)))
  end

  defp parent(ctx, pid) do
    id =
      TurnFixture.thread(ctx, pid, %{
        "runtimeWorkspaceRoots" => roots(ctx),
        "historyMode" => "legacy"
      })

    assert call(pid, "thread/name/set", %{"threadId" => id, "name" => "Owned metadata parent"}) ==
             %{}

    saved = call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]
    assert saved["id"] == id and saved["name"] == "Owned metadata parent"
    assert saved["turns"] == []
    assert File.regular?(saved["path"])
    assert_no_dispatch(ctx, pid)
    {id, saved["path"]}
  end

  defp apply_settings(ctx, pid, id) do
    assert call(pid, "thread/settings/update", %{
             "threadId" => id,
             "disabledPluginIds" => @disabled,
             "collaborationMode" => @collaboration,
             "summary" => "detailed"
           }) == %{}

    events =
      collect(pid, [], fn events ->
        TurnFixture.notification(events, "thread/settings/updated", fn p ->
          p["threadId"] == id and p["threadSettings"]["summary"] == "detailed"
        end) != nil
      end)

    applied = TurnFixture.notification(events, "thread/settings/updated")["threadSettings"]
    assert Map.fetch!(applied, "disabledPluginIds") === @disabled
    assert Map.fetch!(applied, "collaborationMode") === @collaboration
    assert_no_effects(ctx, pid, events)
  end

  defp assert_metadata(ctx, response, disabled) do
    assert Map.fetch!(response, "disabledPluginIds") === disabled
    assert Map.fetch!(response, "runtimeWorkspaceRoots") === roots(ctx)
    assert Map.fetch!(response, "instructionSources") === [ctx.source]
    assert Map.fetch!(response, "sandbox") === @readonly
  end

  defp assert_child(response, parent) do
    child = Map.fetch!(response, "thread")
    refute Map.fetch!(child, "id") == parent
    assert Map.fetch!(child, "forkedFromId") == parent
    assert Map.fetch!(child, "turns") == []
  end

  defp roots(ctx), do: [ctx.fixture.workspace, ctx.extra]

  defp assert_no_dispatch(ctx, pid) do
    assert {:ok, events} = Session.drain(pid)
    assert_no_effects(ctx, pid, events)
  end

  defp assert_no_effects(ctx, pid, events) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             event.kind == :server_request or String.starts_with?(method, "turn/") or
               String.starts_with?(method, "item/")
           end)
  end

  defp collect(pid, events, predicate),
    do: collect(pid, events, predicate, System.monotonic_time(:millisecond) + 20_000)

  defp collect(pid, events, predicate, deadline) do
    assert {:ok, new} = Session.drain(pid)
    events = events ++ new

    cond do
      predicate.(events) ->
        events

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("Metadata settings application deadline")

      true ->
        receive do
        after
          5 -> collect(pid, events, predicate, deadline)
        end
    end
  end
end
