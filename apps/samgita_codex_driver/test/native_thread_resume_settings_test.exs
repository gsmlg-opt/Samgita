defmodule SamgitaCodexDriver.NativeThreadResumeSettingsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [call: 3, upstream_error: 4]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @other_model "owned-resume-model"
  @other_provider "owned_resume_provider"

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
        name = "Owned metadata-only alternate provider"
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
    next_cwd = Path.join(ctx.root, "owned-resume-workspace")
    File.mkdir!(next_cwd)

    ctx
    |> Map.put(:next_cwd, next_cwd)
    |> Map.put(:absent_optional_settings, tags[:absent_optional_settings] == true)
  end

  test "cold resume omission and ordinary nulls report the exact effective defaults", ctx do
    for {label, extra} <- [
          {"omitted", %{}},
          {"null",
           %{
             "model" => nil,
             "modelProvider" => nil,
             "cwd" => nil,
             "approvalPolicy" => nil,
             "approvalsReviewer" => nil,
             "config" => nil
           }}
        ] do
      {pid, id, _saved} = cold_parent(ctx, "Owned resume #{label} defaults")
      response = resume(pid, id, extra)
      # An empty persisted thread has no recorded reasoning effort. Cold resume
      # clears the configured effort unless the request explicitly overrides it.
      assert_settings(response, Map.put(defaults(ctx), "reasoningEffort", nil))
      assert response["thread"]["id"] == id
      assert response["thread"]["name"] == "Owned resume #{label} defaults"
      assert_no_dispatch(ctx, pid)
      assert :ok = Session.close(pid)
    end
  end

  @tag absent_optional_settings: true
  test "absent tier and effort are explicit nulls while a requested null tier selects default",
       ctx do
    for {label, extra, tier} <- [
          {"absent", %{}, nil},
          {"null", %{"serviceTier" => nil}, "default"},
          {"flex", %{"serviceTier" => "flex"}, "flex"}
        ] do
      {pid, id, _saved} = cold_parent(ctx, "Owned resume #{label} tier")
      response = resume(pid, id, extra)

      expected =
        defaults(ctx)
        |> Map.put("serviceTier", tier)
        |> Map.put("reasoningEffort", nil)

      assert_settings(response, expected)
      assert_no_dispatch(ctx, pid)
      assert :ok = Session.close(pid)
    end
  end

  test "cold typed overrides report selected model provider cwd review and profile metadata",
       ctx do
    {pid, id, saved} = cold_parent(ctx, "Owned cold resume override parent")

    response =
      resume(pid, id, %{
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

    assert response["thread"]["id"] == id
    assert response["thread"]["name"] == saved["name"]
    assert_no_dispatch(ctx, pid)
    assert :ok = Session.close(pid)
  end

  test "subscribed loaded resume ignores conflicting overrides and reports live settings", ctx do
    pid = TurnFixture.start(ctx)
    id = start_parent(ctx, pid)
    saved = save(pid, id, "Owned subscribed resume settings")
    bytes = File.read!(saved["path"])
    assert call(pid, "thread/loaded/list", %{})["data"] == [id]

    # thread/start attaches this connection as a subscriber. No unsubscribe or
    # shutdown occurs, so the live session must retain its effective settings.
    response =
      resume(pid, id, %{
        "model" => @other_model,
        "modelProvider" => @other_provider,
        "cwd" => ctx.next_cwd,
        "approvalPolicy" => "never",
        "approvalsReviewer" => "auto_review",
        "permissions" => ":read-only",
        "serviceTier" => nil,
        "config" => %{"model_reasoning_effort" => "high"}
      })

    assert_settings(response, defaults(ctx))
    assert response["thread"]["id"] == id
    # Legacy full-history rejoin reconstructs the summary by rollout path,
    # which does not merge the SQLite-only name set by thread/name/set.
    assert Map.fetch!(response["thread"], "name") == nil
    assert read(pid, id)["name"] == saved["name"]
    assert File.read!(saved["path"]) == bytes
    assert call(pid, "thread/loaded/list", %{})["data"] == [id]
    assert_no_dispatch(ctx, pid)
    assert :ok = Session.close(pid)
  end

  test "malformed cold resume preserves the durable parent and allows explicit recovery", ctx do
    {pid, id, saved} = cold_parent(ctx, "Owned malformed resume parent")
    before = read(pid, id)
    assert before["name"] == "Owned malformed resume parent"
    bytes = File.read!(saved["path"])

    for {field, value, message} <- [
          {"model", 17, "expected a string"},
          {"cwd", false, "expected a string"},
          {"serviceTier", 17, "expected a string"},
          {"approvalsReviewer", "not-a-reviewer", "unknown variant"}
        ] do
      params = %{"threadId" => id, field => value}

      assert {:error, %Error{code: :schema_violation}} =
               Session.request(pid, "thread/resume", params)

      error = upstream_error(pid, "thread/resume", params, validation: :wire)
      assert error["code"] == -32_600
      assert String.starts_with?(error["message"], "Invalid request:")
      assert error["message"] =~ message
      assert_unloaded_parent(ctx, pid, id, before, saved["path"], bytes)
    end

    assert upstream_error(
             pid,
             "thread/resume",
             %{"threadId" => id, "permissions" => ":read-only", "sandbox" => "read-only"},
             validation: :wire
           ) == %{
             "code" => -32_600,
             "message" => "`permissions` cannot be combined with `sandbox`"
           }

    assert_unloaded_parent(ctx, pid, id, before, saved["path"], bytes)
    response = resume(pid, id, %{})
    assert_settings(response, Map.put(defaults(ctx), "reasoningEffort", nil))
    assert response["thread"]["id"] == id
    assert response["thread"]["name"] == before["name"]
    assert call(pid, "thread/loaded/list", %{})["data"] == [id]
    assert_no_dispatch(ctx, pid)
    assert :ok = Session.close(pid)
  end

  defp cold_parent(ctx, name) do
    first = TurnFixture.start(ctx)
    id = start_parent(ctx, first)
    saved = save(first, id, name)
    assert_no_dispatch(ctx, first)
    assert :ok = Session.close(first)
    cold = TurnFixture.start(ctx)
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert read(cold, id)["name"] == name
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    {cold, id, saved}
  end

  defp start_parent(ctx, pid) do
    # Keep the unchanged TurnFixture.thread parameters, but retain the owning
    # method's response so start settings have independent native assertions.
    response =
      call(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "sandbox" => "read-only",
        "approvalPolicy" => "on-request",
        "ephemeral" => false,
        "historyMode" => "legacy"
      })

    assert Map.fetch!(response, "model") === "mock-model"
    assert Map.fetch!(response, "modelProvider") === "fixture"
    assert Map.fetch!(response, "cwd") === ctx.fixture.workspace
    assert Map.fetch!(response, "approvalPolicy") === "on-request"
    assert Map.fetch!(response, "approvalsReviewer") === "user"
    assert Map.fetch!(response, "activePermissionProfile") === nil
    assert Map.fetch!(response, "multiAgentMode") === "explicitRequestOnly"

    expected_tier = if ctx.absent_optional_settings, do: nil, else: "flex"
    expected_effort = if ctx.absent_optional_settings, do: nil, else: "low"
    assert Map.fetch!(response, "serviceTier") === expected_tier
    assert Map.fetch!(response, "reasoningEffort") === expected_effort
    Map.fetch!(Map.fetch!(response, "thread"), "id")
  end

  defp save(pid, id, name) do
    assert call(pid, "thread/name/set", %{"threadId" => id, "name" => name}) == %{}
    saved = read(pid, id)
    assert saved["id"] == id
    assert saved["name"] == name
    assert saved["turns"] == []
    assert File.regular?(saved["path"])
    saved
  end

  defp read(pid, id),
    do: call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]

  defp resume(pid, id, extra),
    do: call(pid, "thread/resume", Map.put(extra, "threadId", id))

  defp defaults(ctx) do
    %{
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "cwd" => ctx.fixture.workspace,
      "approvalPolicy" => "on-request",
      "approvalsReviewer" => "user",
      "serviceTier" => "flex",
      "reasoningEffort" => "low",
      "activePermissionProfile" => nil,
      "multiAgentMode" => "explicitRequestOnly"
    }
  end

  defp assert_settings(response, expected) do
    for {field, value} <- expected do
      assert {field, Map.fetch!(response, field)} === {field, value}
    end
  end

  defp assert_unloaded_parent(ctx, pid, id, before, path, bytes) do
    assert File.read!(path) == bytes
    assert read(pid, id) == before
    assert call(pid, "thread/loaded/list", %{})["data"] == []
    assert_no_dispatch(ctx, pid)
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
