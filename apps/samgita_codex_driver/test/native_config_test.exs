defmodule SamgitaCodexDriver.NativeConfigTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @missing_thread "00000000-0000-4000-8000-000000000000"

  setup context do
    context = TurnFixture.setup(context)
    Map.put(context, :config_path, Path.join(context.fixture.codex_home, "config.toml"))
  end

  test "read defaults omit layers while explicit cwd resolves trusted project origins", context do
    project_dir = Path.join(context.fixture.workspace, ".codex")
    File.mkdir_p!(project_dir)
    File.write!(Path.join(project_dir, "config.toml"), "model_reasoning_effort = 'high'\n")

    File.write!(
      context.config_path,
      File.read!(context.config_path) <>
        "\n[projects.#{JSON.encode!(context.fixture.workspace)}]\ntrust_level = 'trusted'\n"
    )

    pid = start(context)
    default = call(pid, "config/read", %{})
    assert default == call(pid, "config/read", %{"cwd" => nil, "includeLayers" => false})
    refute Map.has_key?(default, "layers")
    assert default["config"]["model"] == "mock-model"
    assert default["origins"]["model"]["name"] == user_source(context)

    scoped =
      call(pid, "config/read", %{"includeLayers" => true, "cwd" => context.fixture.workspace})

    assert scoped["config"]["model_reasoning_effort"] == "high"

    assert scoped["origins"]["model_reasoning_effort"]["name"] == %{
             "type" => "project",
             "dotCodexFolder" => project_dir
           }

    assert Enum.any?(scoped["layers"], &(&1["name"] == user_source(context)))
    refute Enum.any?(scoped["layers"], &(&1["name"]["type"] == "packagedDefaults"))

    assert call(pid, "config/read", %{"cwd" => ".", "includeLayers" => true}) == scoped
    assert call(pid, "config/read", %{}) == default
    assert_idle(context, pid)
  end

  test "value writes merge replace and delete with nullable path and version defaults", context do
    pid = start(context)

    first = write(pid, "desktop", %{"appearanceTheme" => "dark", "preventSleep" => true})
    assert first["filePath"] == context.config_path
    assert first["status"] == "ok"
    assert first["version"] == user_layer(context, pid)["version"]

    second =
      call(pid, "config/value/write", %{
        "keyPath" => "desktop",
        "value" => %{"appearanceTheme" => "light"},
        "mergeStrategy" => "upsert",
        "filePath" => nil,
        "expectedVersion" => first["version"]
      })

    assert second["version"] != first["version"]
    config = call(pid, "config/read", %{})["config"]
    assert config["desktop"]["appearanceTheme"] == "light"
    assert config["desktop"]["preventSleep"] == true

    replaced = write(pid, "desktop", %{"appearanceTheme" => "dark"})
    assert replaced["version"] != second["version"]
    config = call(pid, "config/read", %{})["config"]
    refute Map.has_key?(config["desktop"], "preventSleep")

    deleted =
      call(pid, "config/value/write", %{
        "keyPath" => "desktop.appearanceTheme",
        "value" => nil,
        "mergeStrategy" => "replace",
        "expectedVersion" => nil
      })

    assert deleted["version"] != replaced["version"]
    refute File.read!(context.config_path) =~ "appearanceTheme"
    refute get_in(call(pid, "config/read", %{}), ["config", "desktop", "appearanceTheme"])

    persisted = File.read!(context.config_path)

    stale =
      upstream_error(pid, "config/value/write", %{
        "keyPath" => "desktop.appearanceTheme",
        "value" => "light",
        "mergeStrategy" => "replace",
        "expectedVersion" => replaced["version"]
      })

    assert_write_error(stale, "configVersionConflict")
    assert File.read!(context.config_path) == persisted
    assert user_layer(context, pid)["version"] == deleted["version"]
    assert :ok = Session.close(pid)
    restarted = start(context)
    assert user_layer(context, restarted)["version"] == deleted["version"]
    refute File.read!(context.config_path) =~ "appearanceTheme"
    assert_idle(context, restarted)
  end

  test "invalid batches are atomic and successful reload writes survive process restart",
       context do
    pid = start(context)
    id = thread(context, pid)
    baseline = File.read!(context.config_path)
    version = user_layer(context, pid)["version"]

    error =
      upstream_error(pid, "config/batchWrite", %{
        "expectedVersion" => version,
        "reloadUserConfig" => true,
        "edits" => [edit("desktop.appearanceTheme", "dark"), edit("model", 42)]
      })

    assert_write_error(error, "configValidationError")
    assert File.read!(context.config_path) == baseline
    assert user_layer(context, pid)["version"] == version

    batch =
      call(pid, "config/batchWrite", %{
        "filePath" => nil,
        "expectedVersion" => version,
        "reloadUserConfig" => true,
        "edits" => [
          edit("desktop.appearanceTheme", "dark"),
          edit("features.auth_elicitation", false)
        ]
      })

    assert batch["status"] == "ok"
    refute batch["version"] == version
    refute feature(pid, "auth_elicitation", %{"threadId" => id})["enabled"]
    assert call(pid, "config/read", %{})["config"]["desktop"]["appearanceTheme"] == "dark"
    persisted = File.read!(context.config_path)

    conflict =
      upstream_error(pid, "config/batchWrite", %{
        "expectedVersion" => version,
        "edits" => [edit("desktop.appearanceTheme", "light")]
      })

    assert_write_error(conflict, "configVersionConflict")
    assert File.read!(context.config_path) == persisted

    noop = call(pid, "config/batchWrite", %{"edits" => [], "expectedVersion" => batch["version"]})
    assert noop["version"] == batch["version"]
    assert File.read!(context.config_path) == persisted
    assert_idle(context, pid)
    assert :ok = Session.close(pid)

    restarted = start(context)
    refute feature(restarted, "auth_elicitation")["enabled"]
    assert call(restarted, "config/read", %{})["config"]["desktop"]["appearanceTheme"] == "dark"
    assert user_layer(context, restarted)["version"] == batch["version"]
    assert_idle(context, restarted)
  end

  test "write validation and nonuser paths preserve disk state and request health", context do
    pid = start(context)
    baseline = File.read!(context.config_path)

    for {key, value} <- [
          {"", true},
          {"desktop..appearanceTheme", "dark"},
          {"profile", "old"},
          {"profiles.old.model", "mock-model"},
          {"model", 42}
        ] do
      error = upstream_error(pid, "config/value/write", edit(key, value))
      assert_write_error(error, "configValidationError")
      assert File.read!(context.config_path) == baseline
    end

    other = Path.join(context.root, "unowned.toml")

    error =
      upstream_error(
        pid,
        "config/value/write",
        Map.put(edit("model", "mock-model"), "filePath", other)
      )

    assert_write_error(error, "configLayerReadonly")
    refute File.exists?(other)

    for {method, params} <- [
          {"config/read", %{"includeLayers" => nil}},
          {"config/read", %{"cwd" => 42}},
          {"config/value/write", Map.delete(edit("model", "mock-model"), "value")},
          {"config/batchWrite", %{"edits" => [], "reloadUserConfig" => nil}},
          {"experimentalFeature/enablement/set", %{"enablement" => nil}}
        ] do
      error = upstream_error(pid, method, params, validation: :wire)
      assert error["code"] == -32_600
      assert error["message"] =~ "Invalid request"
      assert File.read!(context.config_path) == baseline
    end

    assert call(pid, "config/read", %{})["config"]["model"] == "mock-model"
    assert_idle(context, pid)
  end

  test "requirements distinguish unrestricted null policy from forced local login restrictions",
       context do
    pid = start(context)

    assert call(pid, "configRequirements/read", nil) == %{
             "requirements" => nil,
             "supportsIndependentSpeedModes" => true
           }

    assert_idle(context, pid)
    assert :ok = Session.close(pid)

    File.write!(
      context.config_path,
      "forced_login_method = 'api'\n" <> File.read!(context.config_path)
    )

    restricted = start(context)
    response = call(restricted, "configRequirements/read", nil)
    assert response["supportsIndependentSpeedModes"] == true
    assert response["requirements"]["allowedLoginMethods"] == ["api"]
    assert Map.has_key?(response["requirements"], "modelProvider")
    assert response["requirements"]["modelProvider"] == nil
    assert_idle(context, restricted)
  end

  test "feature catalog pagination preserves metadata and validates cursors and thread scope",
       context do
    pid = start(context)
    all = call(pid, "experimentalFeature/list", %{})
    assert all["nextCursor"] == nil

    assert all ==
             call(pid, "experimentalFeature/list", %{
               "cursor" => nil,
               "limit" => nil,
               "threadId" => nil
             })

    assert all["data"] != []
    assert length(Enum.uniq_by(all["data"], & &1["name"])) == length(all["data"])

    for feature <- all["data"] do
      assert is_boolean(feature["enabled"]) and is_boolean(feature["defaultEnabled"])
      assert feature["stage"] in ["beta", "underDevelopment", "stable", "deprecated", "removed"]

      for key <- ["displayName", "description", "announcement"] do
        assert Map.has_key?(feature, key)

        if feature["stage"] == "beta",
          do: assert(is_binary(feature[key])),
          else: assert(is_nil(feature[key]))
      end
    end

    zero = call(pid, "experimentalFeature/list", %{"limit" => 0})
    assert zero["data"] == Enum.take(all["data"], 1)
    assert zero["nextCursor"] == "1"
    assert pages(pid, nil, []) == all["data"]
    count = length(all["data"])

    assert call(pid, "experimentalFeature/list", %{"cursor" => to_string(count)}) == %{
             "data" => [],
             "nextCursor" => nil
           }

    for {params, message} <- [
          {%{"cursor" => "invalid"}, "invalid cursor"},
          {%{"cursor" => to_string(count + 1)}, "exceeds total feature flags"},
          {%{"threadId" => "invalid"}, "invalid thread id"},
          {%{"threadId" => @missing_thread}, "thread not found"}
        ] do
      error = upstream_error(pid, "experimentalFeature/list", params)
      assert error["code"] == -32_600
      assert error["message"] =~ message
    end

    id = thread(context, pid)
    assert call(pid, "experimentalFeature/list", %{"threadId" => id}) == all
    assert_idle(context, pid)
  end

  test "runtime enablement updates named supported flags without overriding disk or surviving restart",
       context do
    File.write!(
      context.config_path,
      File.read!(context.config_path) <> "\n[features]\nmcp_2026_07_28 = false\n"
    )

    baseline = File.read!(context.config_path)
    pid = start(context)
    initial = feature(pid, "auth_elicitation")["enabled"]
    assert initial == true
    id = thread(context, pid)

    assert call(pid, "experimentalFeature/enablement/set", %{
             "enablement" => %{
               "auth_elicitation" => false,
               "mcp_2026_07_28" => true,
               "unknown_feature" => true,
               "shell_tool" => false
             }
           }) == %{"enablement" => %{"auth_elicitation" => false, "mcp_2026_07_28" => true}}

    refute feature(pid, "auth_elicitation")["enabled"]
    refute feature(pid, "auth_elicitation", %{"threadId" => id})["enabled"]
    refute feature(pid, "mcp_2026_07_28")["enabled"]

    assert call(pid, "experimentalFeature/enablement/set", %{"enablement" => %{}}) == %{
             "enablement" => %{}
           }

    refute feature(pid, "auth_elicitation")["enabled"]

    assert call(pid, "experimentalFeature/enablement/set", %{
             "enablement" => %{"mcp_2026_07_28" => false}
           }) == %{"enablement" => %{"mcp_2026_07_28" => false}}

    refute feature(pid, "auth_elicitation")["enabled"]
    assert call(pid, "config/read", %{})["config"]["features"]["auth_elicitation"] == false

    assert call(pid, "experimentalFeature/enablement/set", %{
             "enablement" => %{"auth_elicitation" => true}
           }) == %{"enablement" => %{"auth_elicitation" => true}}

    assert feature(pid, "auth_elicitation")["enabled"]
    assert feature(pid, "auth_elicitation", %{"threadId" => id})["enabled"]

    assert call(pid, "experimentalFeature/enablement/set", %{
             "enablement" => %{"auth_elicitation" => false}
           }) == %{"enablement" => %{"auth_elicitation" => false}}

    refute feature(pid, "auth_elicitation")["enabled"]
    assert File.read!(context.config_path) == baseline
    assert_idle(context, pid)
    assert :ok = Session.close(pid)

    restarted = start(context)
    assert feature(restarted, "auth_elicitation")["enabled"] == initial
    refute feature(restarted, "mcp_2026_07_28")["enabled"]
    assert File.read!(context.config_path) == baseline
    assert_idle(context, restarted)
  end

  defp edit(key, value), do: %{"keyPath" => key, "value" => value, "mergeStrategy" => "replace"}
  defp write(pid, key, value), do: call(pid, "config/value/write", edit(key, value))

  defp user_source(context),
    do: %{"type" => "user", "file" => context.config_path, "profile" => nil}

  defp user_layer(context, pid) do
    call(pid, "config/read", %{"includeLayers" => true})["layers"]
    |> Enum.find(&(&1["name"] == user_source(context)))
    |> tap(&assert(is_map(&1)))
  end

  defp assert_write_error(error, reason) do
    assert error["code"] == -32_600
    assert error["data"] == %{"config_write_error_code" => reason}
  end

  defp feature(pid, name, params \\ %{}) do
    call(pid, "experimentalFeature/list", params)["data"]
    |> Enum.find(&(&1["name"] == name))
    |> tap(&assert(is_map(&1)))
  end

  defp pages(pid, cursor, acc) do
    page = call(pid, "experimentalFeature/list", %{"limit" => 13, "cursor" => cursor})
    acc = acc ++ page["data"]
    if page["nextCursor"], do: pages(pid, page["nextCursor"], acc), else: acc
  end

  defp assert_idle(context, pid) do
    assert ModelFixture.requests(context.fixture) == []
    assert Session.status(pid).phase == :ready
    assert Session.status(pid).pending == 0
  end
end
