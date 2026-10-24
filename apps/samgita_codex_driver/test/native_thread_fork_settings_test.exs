defmodule SamgitaCodexDriver.NativeThreadForkSettingsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [call: 3, upstream_error: 4]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @other_model "owned-fork-model"
  @other_provider "owned_fork_provider"

  setup tags do
    ctx = TurnFixture.setup(tags)

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    TurnFixture.configure_model(ctx, %{
      "supported_reasoning_levels" => [
        %{"effort" => "low", "description" => "Synthetic low metadata"},
        %{"effort" => "high", "description" => "Synthetic high metadata"}
      ]
    })

    catalog = Path.join(ctx.fixture.codex_home, "turn-models.json")
    %{"models" => [model]} = catalog |> File.read!() |> JSON.decode!()
    File.write!(catalog, JSON.encode!(%{"models" => [model, %{model | "slug" => @other_model}]}))
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    optional =
      if tags[:absent_optional_settings],
        do: "",
        else: "model_reasoning_effort = \"low\"\nservice_tier = \"flex\"\n"

    File.write!(
      config,
      optional <>
        "cli_auth_credentials_store = \"ephemeral\"\n" <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        """

        [model_providers.#{@other_provider}]
        name = "Owned metadata-only alias of the existing loopback fixture"
        base_url = #{JSON.encode!(ctx.fixture.url <> "/v1")}
        wire_api = "responses"
        requires_openai_auth = false
        supports_websockets = false
        request_max_retries = 0
        stream_max_retries = 0
        [features]
        apps = false
        plugins = false
        recommended_plugins = false
        shell_snapshot = false
        fast_mode = true
        """
    )

    before = File.read!(config)
    on_exit(fn -> assert File.read!(config) == before end)
    next_cwd = Path.join(ctx.root, "owned-fork-workspace")
    File.mkdir!(next_cwd)

    ctx
    |> Map.put(:next_cwd, next_cwd)
    |> Map.put(:absent_optional_settings, tags[:absent_optional_settings] == true)
  end

  test "loaded empty parents fork with omitted or ordinary null effective settings", ctx do
    pid = TurnFixture.start(ctx)

    for mode <- ["legacy", "paginated"] do
      {parent, bytes} = parent(ctx, pid, mode, "Owned loaded fork #{mode}")

      for extra <- [
            %{},
            %{
              "model" => nil,
              "modelProvider" => nil,
              "cwd" => nil,
              "approvalPolicy" => nil,
              "approvalsReviewer" => nil,
              "permissions" => nil,
              "config" => nil,
              "path" => nil
            }
          ] do
        response = fork_child(ctx, pid, parent, bytes, extra)
        assert_settings(response, defaults(ctx))
      end
    end

    assert :ok = Session.close(pid)
  end

  @tag absent_optional_settings: true
  test "fork optional settings distinguish omitted and explicit null tiers without effort", ctx do
    pid = TurnFixture.start(ctx)
    {parent, bytes} = parent(ctx, pid, "legacy", "Owned absent fork settings")

    for {extra, tier} <- [
          {%{}, nil},
          {%{"serviceTier" => nil}, "default"},
          {%{"serviceTier" => "flex"}, "flex"}
        ] do
      response = fork_child(ctx, pid, parent, bytes, extra)
      assert_settings(response, Map.put(defaults(ctx), "serviceTier", tier))
    end

    assert :ok = Session.close(pid)
  end

  test "cold fork overrides select exact owned model provider cwd review and readonly profile",
       ctx do
    for mode <- ["legacy", "paginated"] do
      {pid, parent, bytes} = cold_parent(ctx, mode, "Owned override fork #{mode}")

      response =
        fork_child(ctx, pid, parent, bytes, %{
          "model" => @other_model,
          "modelProvider" => @other_provider,
          "cwd" => ctx.next_cwd,
          "approvalPolicy" => "never",
          "approvalsReviewer" => "guardian_subagent",
          "permissions" => ":read-only",
          "serviceTier" => nil,
          "config" => %{"model_reasoning_effort" => "high"}
        })

      assert_settings(response, %{
        "model" => @other_model,
        "modelProvider" => @other_provider,
        "cwd" => ctx.next_cwd,
        "approvalPolicy" => "never",
        "approvalsReviewer" => "auto_review",
        "serviceTier" => "default",
        "reasoningEffort" => "high",
        "activePermissionProfile" => %{"id" => ":read-only", "extends" => nil},
        "multiAgentMode" => "explicitRequestOnly"
      })

      assert :ok = Session.close(pid)
    end
  end

  test "standalone fork sandbox selects readonly without changing parent or sibling", ctx do
    pid = TurnFixture.start(ctx)
    readonly = %{"type" => "readOnly", "networkAccess" => false}
    named_profile = %{"id" => ":read-only", "extends" => nil}
    parent_settings = Map.put(defaults(ctx), "activePermissionProfile", named_profile)

    # Keep every source at read-only authority. A named parent profile makes an
    # ignored sandbox override observable: the selected child must report nil.
    {source, source_bytes} =
      parent(ctx, pid, "paginated", "Owned standalone sandbox fork", %{
        "sandbox" => nil,
        "permissions" => ":read-only"
      })

    source_id = Map.fetch!(source, "id")
    resumed_source = call(pid, "thread/resume", %{"threadId" => source_id})
    assert_settings(resumed_source, Map.put(parent_settings, "sandbox", readonly))
    assert_parent(pid, source, source_bytes)
    assert_no_dispatch(ctx, pid)

    inherited =
      for {extra, presence} <- [{%{}, :error}, {%{"sandbox" => nil}, {:ok, nil}}] do
        assert Map.fetch(extra, "sandbox") === presence
        refute Map.has_key?(extra, "permissions")
        response = fork_child(ctx, pid, source, source_bytes, extra)
        assert_settings(response, Map.put(parent_settings, "sandbox", readonly))
        saved = read(pid, Map.fetch!(response["thread"], "id"))
        {saved, File.read!(Map.fetch!(saved, "path"))}
      end

    inherited_ids = Enum.map(inherited, fn {saved, _bytes} -> Map.fetch!(saved, "id") end)
    before_rejection = MapSet.new([source_id | inherited_ids])
    assert loaded(pid) == before_rejection

    for {value, reason} <- [
          {17, "invalid type: integer `17`"},
          {"not-a-sandbox", "unknown variant `not-a-sandbox`"}
        ] do
      params = %{"threadId" => source_id, "sandbox" => value}
      refute Map.has_key?(params, "permissions")

      assert {:error, %Error{code: :schema_violation}} =
               Session.request(pid, "thread/fork", params)

      assert %{"code" => -32_600, "message" => message} =
               upstream_error(pid, "thread/fork", params, validation: :wire)

      assert String.starts_with?(message, "Invalid request: ")
      assert message =~ reason
      assert loaded(pid) == before_rejection
      assert_parent(pid, source, source_bytes)

      for {saved, bytes} <- inherited do
        assert_parent(pid, saved, bytes)
      end

      assert_no_dispatch(ctx, pid)
    end

    sibling_settings =
      Map.merge(parent_settings, %{"cwd" => ctx.next_cwd, "approvalPolicy" => "never"})

    sibling =
      fork_child(ctx, pid, source, source_bytes, %{
        "cwd" => ctx.next_cwd,
        "approvalPolicy" => "never"
      })

    assert_settings(sibling, Map.put(sibling_settings, "sandbox", readonly))
    sibling_id = Map.fetch!(sibling["thread"], "id")
    saved_sibling = read(pid, sibling_id)
    sibling_bytes = File.read!(Map.fetch!(saved_sibling, "path"))

    override = %{"sandbox" => "read-only"}
    refute Map.has_key?(override, "permissions")
    selected = fork_child(ctx, pid, source, source_bytes, override)
    assert_settings(selected, Map.put(defaults(ctx), "sandbox", readonly))
    selected_id = Map.fetch!(selected["thread"], "id")
    refute selected_id == sibling_id
    expected_loaded = MapSet.new([source_id, sibling_id, selected_id] ++ inherited_ids)
    assert loaded(pid) == expected_loaded

    for {id, expected} <- [
          {source_id, parent_settings},
          {sibling_id, sibling_settings},
          {selected_id, defaults(ctx)}
        ] do
      response = call(pid, "thread/resume", %{"threadId" => id})
      assert_settings(response, Map.put(expected, "sandbox", readonly))
    end

    assert_parent(pid, source, source_bytes)
    assert_parent(pid, saved_sibling, sibling_bytes)
    assert_no_dispatch(ctx, pid)
    workspace_before = File.ls!(ctx.fixture.workspace) |> Enum.sort()
    sibling_workspace_before = File.ls!(ctx.next_cwd) |> Enum.sort()

    # A normal assistant-only turn is permitted under the effective sandbox.
    # There is no turn sandbox/profile override and no tool approval shortcut.
    text = "Owned standalone sandbox permitted assistant turn: λ🙂"
    turn = TurnFixture.start_turn(pid, selected_id, [%{"type" => "text", "text" => text}])
    events = TurnFixture.finish_turn(pid, selected_id, turn)

    assert [request] = ModelFixture.requests(ctx.fixture)
    assert request["model"] == "mock-model"

    assert Enum.any?(request["input"], fn item ->
             item["role"] == "user" and
               %{"type" => "input_text", "text" => text} in Map.get(item, "content", [])
           end)

    assert %{
             "threadId" => ^selected_id,
             "turnId" => ^turn,
             "item" => %{
               "type" => "agentMessage",
               "text" => "Deterministic local fixture answer"
             }
           } =
             TurnFixture.notification(
               events,
               "item/completed",
               &(&1["item"]["type"] == "agentMessage")
             )

    refute Enum.any?(events, &(&1.kind == :server_request or &1.wire["method"] == "error"))

    # Read the loaded effective settings again, independently of the earlier
    # fork responses. The completed child turn must not change either source.
    for {id, expected} <- [
          {source_id, parent_settings},
          {sibling_id, sibling_settings},
          {selected_id, defaults(ctx)}
        ] do
      response = call(pid, "thread/resume", %{"threadId" => id})
      assert_settings(response, Map.put(expected, "sandbox", readonly))
    end

    assert_parent(pid, source, source_bytes)
    assert_parent(pid, saved_sibling, sibling_bytes)
    assert loaded(pid) == expected_loaded
    assert ModelFixture.requests(ctx.fixture) == [request]
    assert File.ls!(ctx.fixture.workspace) |> Enum.sort() == workspace_before
    assert File.ls!(ctx.next_cwd) |> Enum.sort() == sibling_workspace_before
    assert Session.interaction_outcomes(pid) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, interactions: 0} = Session.status(pid)
    assert :ok = Session.close(pid)
  end

  test "cold path-selected forks identify the actual source and leave the parent unloaded", ctx do
    for mode <- ["legacy", "paginated"] do
      {pid, parent, bytes} = cold_parent(ctx, mode, "Owned path fork #{mode}")

      # The pinned path contract ignores threadId when a nonempty path is supplied.
      response =
        fork_child(ctx, pid, parent, bytes, %{
          "threadId" => "not-a-valid-thread-id",
          "path" => Map.fetch!(parent, "path")
        })

      assert_settings(response, defaults(ctx))
      assert :ok = Session.close(pid)
    end
  end

  test "invalid fork types and paths preserve the cold parent before explicit recovery", ctx do
    {pid, parent, bytes} = cold_parent(ctx, "legacy", "Owned rejected fork survivor")
    id = Map.fetch!(parent, "id")

    for {field, value, message} <- [
          {"model", 17, "Invalid request: invalid type: integer `17`, expected a string"},
          {"modelProvider", 17, "Invalid request: invalid type: integer `17`, expected a string"},
          {"cwd", false, "Invalid request: invalid type: boolean `false`, expected a string"}
        ] do
      params = %{"threadId" => id, field => value}

      assert {:error, %Error{code: :schema_violation}} =
               Session.request(pid, "thread/fork", params)

      assert upstream_error(pid, "thread/fork", params, validation: :wire) == %{
               "code" => -32_600,
               "message" => message
             }

      assert_parent(pid, parent, bytes)
      assert loaded(pid) == MapSet.new()
      assert_no_dispatch(ctx, pid)
    end

    missing_path = Path.join(ctx.root, "owned-missing-rollout.jsonl")
    refute File.exists?(missing_path)

    for {path, reason} <- [
          {ctx.fixture.workspace, "path is a directory"},
          {missing_path, "file does not exist"}
        ] do
      assert upstream_error(
               pid,
               "thread/fork",
               %{"threadId" => id, "path" => path},
               validation: :wire
             ) == %{
               "code" => -32_600,
               "message" => "failed to resolve rollout path `#{path}`: #{reason}"
             }

      assert_parent(pid, parent, bytes)
      assert loaded(pid) == MapSet.new()
      assert_no_dispatch(ctx, pid)
    end

    assert upstream_error(
             pid,
             "thread/fork",
             %{"threadId" => id, "permissions" => ":read-only", "sandbox" => "read-only"},
             validation: :wire
           ) == %{
             "code" => -32_600,
             "message" => "`permissions` cannot be combined with `sandbox`"
           }

    assert_parent(pid, parent, bytes)
    assert loaded(pid) == MapSet.new()
    assert_no_dispatch(ctx, pid)
    response = fork_child(ctx, pid, parent, bytes, %{})
    assert_settings(response, defaults(ctx))
    assert :ok = Session.close(pid)
  end

  defp parent(ctx, pid, mode, name, extra \\ %{}) do
    id = TurnFixture.thread(ctx, pid, Map.merge(%{"historyMode" => mode}, extra))
    assert call(pid, "thread/name/set", %{"threadId" => id, "name" => name}) == %{}
    parent = read(pid, id)
    assert Map.fetch!(parent, "id") == id
    assert Map.fetch!(parent, "name") == name
    assert Map.fetch!(parent, "historyMode") == mode
    assert Map.fetch!(parent, "turns") == []
    assert File.regular?(Map.fetch!(parent, "path"))
    bytes = File.read!(Map.fetch!(parent, "path"))
    assert_no_dispatch(ctx, pid)
    {parent, bytes}
  end

  defp cold_parent(ctx, mode, name) do
    first = TurnFixture.start(ctx)
    {saved, bytes} = parent(ctx, first, mode, name)
    assert :ok = Session.close(first)
    cold = TurnFixture.start(ctx)
    assert loaded(cold) == MapSet.new()
    parent = read(cold, Map.fetch!(saved, "id"))
    assert Map.fetch!(parent, "name") == name
    assert Map.fetch!(parent, "turns") == []
    assert Map.fetch!(parent, "path") == Map.fetch!(saved, "path")
    assert File.read!(Map.fetch!(parent, "path")) == bytes
    assert loaded(cold) == MapSet.new()
    assert_no_dispatch(ctx, cold)
    {cold, parent, bytes}
  end

  defp fork_child(ctx, pid, parent, bytes, extra) do
    before = loaded(pid)
    id = Map.fetch!(parent, "id")
    response = call(pid, "thread/fork", Map.merge(%{"threadId" => id}, extra))
    child = Map.fetch!(response, "thread")
    child_id = Map.fetch!(child, "id")
    assert is_binary(child_id) and byte_size(child_id) > 0
    refute child_id == id
    refute MapSet.member?(before, child_id)
    assert Map.fetch!(child, "forkedFromId") == id
    # Legacy path selection reads rollout/index metadata; paginated path
    # selection replaces that metadata with the SQLite display record.
    expected_name =
      if is_binary(extra["path"]) and parent["historyMode"] == "legacy",
        do: nil,
        else: Map.fetch!(parent, "name")

    assert Map.fetch!(child, "name") == expected_name
    assert Map.fetch!(child, "historyMode") == Map.fetch!(parent, "historyMode")
    assert Map.fetch!(child, "turns") == []
    child_path = Map.fetch!(child, "path")
    assert File.regular?(child_path)
    refute child_path == Map.fetch!(parent, "path")
    assert loaded(pid) == MapSet.put(before, child_id)
    assert_parent(pid, parent, bytes)
    assert_no_dispatch(ctx, pid)
    response
  end

  defp read(pid, id),
    do: call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]

  defp loaded(pid),
    do: MapSet.new(Map.fetch!(call(pid, "thread/loaded/list", %{}), "data"))

  defp assert_parent(pid, parent, bytes) do
    assert read(pid, Map.fetch!(parent, "id")) == parent
    assert File.read!(Map.fetch!(parent, "path")) == bytes
  end

  defp defaults(ctx) do
    %{
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "cwd" => ctx.fixture.workspace,
      "approvalPolicy" => "on-request",
      "approvalsReviewer" => "user",
      "serviceTier" => if(ctx.absent_optional_settings, do: nil, else: "flex"),
      "reasoningEffort" => if(ctx.absent_optional_settings, do: nil, else: "low"),
      "activePermissionProfile" => nil,
      "multiAgentMode" => "explicitRequestOnly"
    }
  end

  defp assert_settings(response, expected) do
    for {field, value} <- expected do
      assert {field, Map.fetch!(response, field)} === {field, value}
    end
  end

  defp assert_no_dispatch(ctx, pid) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, interactions: 0} = Session.status(pid)
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request))

    for method <- ["turn/started", "turn/completed", "item/started", "item/completed"] do
      refute TurnFixture.notification(events, method)
    end
  end
end
