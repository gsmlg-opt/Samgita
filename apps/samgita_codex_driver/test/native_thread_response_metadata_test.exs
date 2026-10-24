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
