defmodule SamgitaCodexDriver.NativeManagedRequirementsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ManagedRequirementsFixture, Session, TurnFixture}
  import ManagedRequirementsFixture, only: [close: 2, assert_idle: 1]
  import TurnFixture, only: [call: 3, upstream_error: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @requirements """
  allowed_approval_policies = ["untrusted", "on-request"]
  allowed_approvals_reviewers = ["user"]
  allowed_sandbox_modes = ["read-only"]
  allowed_web_search_modes = []
  allow_managed_hooks_only = true
  allow_browser_and_computer_use = false
  allow_appshots = false
  allow_remote_control = false
  check_for_update_on_startup = false
  allow_login_shell = false
  additional_developer_instructions = "Synthetic managed policy only"
  [feedback]
  enabled = false
  """

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha

    for tool <- ~w(python3 unshare ip mount),
        do: assert(System.find_executable(tool), "BLOCKED_ENV: #{tool} required")

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-managed-requirements-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    for dir <- ~w(home codex workspace tmp system), do: File.mkdir_p!(Path.join(root, dir))
    on_exit(fn -> File.rm_rf!(root) end)
    requirements = Path.join(root, "system/requirements.toml")
    File.write!(requirements, @requirements)
    config = Path.join(root, "codex/config.toml")

    File.write!(config, """
    model = "mock-model"
    model_provider = "fixture"
    approval_policy = "on-request"
    sandbox_mode = "read-only"
    web_search = "disabled"
    cli_auth_credentials_store = "ephemeral"
    check_for_update_on_startup = false
    allow_login_shell = false
    chatgpt_base_url = "http://127.0.0.1:9"
    openai_base_url = "http://127.0.0.1:9/v1"
    [features]
    apps = false
    plugins = false
    recommended_plugins = false
    shell_snapshot = false
    [model_providers.fixture]
    name = "Nonexecuting managed requirements fixture"
    base_url = "http://127.0.0.1:9/v1"
    wire_api = "responses"
    requires_openai_auth = false
    supports_websockets = false
    request_max_retries = 0
    stream_max_retries = 0
    """)

    %{binary: Path.expand(binary), root: root, config: config, requirements: requirements}
  end

  test "actual managed requirements retain restrictive values and normalize empty web search choices",
       ctx do
    pid = start(ctx)
    response = call(pid, "configRequirements/read", nil)
    assert response["supportsIndependentSpeedModes"] == true
    requirements = response["requirements"]
    assert requirements["allowedApprovalPolicies"] === ["untrusted", "on-request"]
    assert requirements["allowedApprovalsReviewers"] === ["user"]
    assert requirements["allowedSandboxModes"] === ["read-only"]
    assert requirements["allowedWebSearchModes"] === ["disabled"]
    assert requirements["allowManagedHooksOnly"] === true
    assert requirements["additionalDeveloperInstructions"] === "Synthetic managed policy only"

    for key <- [
          "allowBrowserAndComputerUse",
          "allowAppshots",
          "allowRemoteControl",
          "checkForUpdateOnStartup",
          "allowLoginShell"
        ],
        do: assert(requirements[key] === false)

    assert requirements["feedback"] === %{"enabled" => false}
    effective = call(pid, "config/read", %{})["config"]
    assert effective["check_for_update_on_startup"] === false
    assert effective["allow_login_shell"] === false
    assert effective["feedback"]["enabled"] === false
    assert File.read!(ctx.requirements) == @requirements
    assert_idle(pid)
    close(ctx, pid)
  end

  test "legacy managed layer narrows the system approval list without losing unrelated requirements",
       ctx do
    pid = start(ctx)
    baseline = call(pid, "configRequirements/read", nil)["requirements"]
    assert baseline["allowedApprovalPolicies"] === ["untrusted", "on-request"]
    close(ctx, pid)
    config = File.read!(ctx.config)

    File.write!(Path.join(ctx.root, "system/managed_config.toml"), """
    approval_policy = "on-request"
    approvals_reviewer = "user"
    sandbox_mode = "read-only"
    """)

    next = start(ctx)
    requirements = call(next, "configRequirements/read", nil)["requirements"]
    assert requirements === Map.put(baseline, "allowedApprovalPolicies", ["on-request"])
    assert call(next, "config/read", %{})["config"]["approval_policy"] == "on-request"
    assert File.read!(ctx.config) == config
    assert File.read!(ctx.requirements) == @requirements
    assert_idle(next)
    close(ctx, next)
  end

  test "managed exact field rejects a whole batch before any user config write", ctx do
    pid = start(ctx)
    baseline = File.read!(ctx.config)
    before = call(pid, "configRequirements/read", nil)

    error =
      upstream_error(pid, "config/batchWrite", %{
        "edits" => [
          %{
            "keyPath" => "desktop.appearanceTheme",
            "value" => "dark",
            "mergeStrategy" => "replace"
          },
          %{
            "keyPath" => "check_for_update_on_startup",
            "value" => true,
            "mergeStrategy" => "replace"
          }
        ]
      })

    assert error["code"] == -32_600
    assert error["data"] === %{"config_write_error_code" => "configRequirementReadonly"}

    assert error["message"] ==
             "`check_for_update_on_startup` is managed by requirements and cannot be changed"

    assert File.read!(ctx.config) == baseline
    assert call(pid, "configRequirements/read", nil) === before
    refute get_in(call(pid, "config/read", %{}), ["config", "desktop", "appearanceTheme"])
    assert_idle(pid)
    close(ctx, pid)
  end

  test "invalid managed file fails an explicit read and a repaired file restores the same policy",
       ctx do
    pid = start(ctx)
    baseline = call(pid, "configRequirements/read", nil)
    config = File.read!(ctx.config)

    try do
      # Only this test's synthetic source is changed; the child mount stays read-only.
      File.write!(ctx.requirements, "allowed_sandbox_modes = [\n")
      error = upstream_error(pid, "configRequirements/read", nil)
      assert error["code"] == -32_603
      assert error["message"] =~ "failed to read configuration layers:"
      assert error["message"] =~ "/etc/codex/requirements.toml"
      assert error["message"] =~ "failed to parse requirements layer"
      assert Session.status(pid).phase == :ready
      assert File.read!(ctx.config) == config
    after
      File.write!(ctx.requirements, @requirements)
    end

    assert call(pid, "configRequirements/read", nil) === baseline
    assert_idle(pid)
    close(ctx, pid)
  end

  test "workspace marker excludes a trusted owned ancestor project configuration", ctx do
    workspace = Path.join(ctx.root, "workspace")
    ancestor_codex = Path.join(ctx.root, ".codex")
    ancestor_config = Path.join(ancestor_codex, "config.toml")
    ancestor_git = Path.join(ctx.root, ".git")
    File.mkdir_p!(ancestor_codex)
    File.mkdir_p!(ancestor_git)
    File.write!(Path.join(ancestor_git, "HEAD"), "ref: refs/heads/owned-ancestor\n")
    ancestor_contents = "model_reasoning_effort = 'high'\n"
    File.write!(ancestor_config, ancestor_contents)

    # Both synthetic roots are trusted, so disabled project layers cannot hide
    # a missing workspace discovery boundary. No execution method is invoked.
    File.write!(
      ctx.config,
      "model_reasoning_effort = 'low'\n" <>
        File.read!(ctx.config) <>
        """

        [projects.#{JSON.encode!(ctx.root)}]
        trust_level = 'trusted'
        [projects.#{JSON.encode!(workspace)}]
        trust_level = 'trusted'
        """
    )

    user_contents = File.read!(ctx.config)
    pid = start(ctx)
    scoped_params = %{"cwd" => workspace, "includeLayers" => true}
    scoped = call(pid, "config/read", scoped_params)
    assert scoped["config"]["model"] == "mock-model"
    assert scoped["config"]["model_reasoning_effort"] == "low"

    assert scoped["origins"]["model_reasoning_effort"]["name"] == %{
             "type" => "user",
             "file" => ctx.config,
             "profile" => nil
           }

    refute Enum.any?(scoped["layers"], fn layer ->
             layer["name"]["type"] == "project" and
               layer["name"]["dotCodexFolder"] == ancestor_codex
           end)

    # Positive control: the same owned ancestor policy is effective when that
    # root is requested explicitly, rather than through the marked workspace.
    ancestor = call(pid, "config/read", %{"cwd" => ctx.root, "includeLayers" => true})
    assert ancestor["config"]["model_reasoning_effort"] == "high"

    assert ancestor["origins"]["model_reasoning_effort"]["name"] == %{
             "type" => "project",
             "dotCodexFolder" => ancestor_codex
           }

    assert call(pid, "config/read", scoped_params) === scoped
    assert File.read!(ancestor_config) === ancestor_contents
    assert File.read!(ctx.config) === user_contents
    assert_idle(pid)
    close(ctx, pid)
  end

  test "managed path requirements overlay exact owned paths across a cold restart", ctx do
    paths = managed_paths(ctx)
    pid = start(ctx)
    assert_managed_paths(pid, paths)
    assert_path_sources(ctx, paths)
    assert_idle(pid)
    close(ctx, pid)

    restarted = start(ctx)
    assert_managed_paths(restarted, paths)
    assert_path_sources(ctx, paths)
    assert_idle(restarted)
    close(ctx, restarted)
  end

  test "managed paths reject writes atomically and recover from typed policy read errors", ctx do
    paths = managed_paths(ctx)
    pid = start(ctx)
    baseline = assert_managed_paths(pid, paths)

    edit = fn key, value ->
      %{"keyPath" => key, "value" => value, "mergeStrategy" => "replace"}
    end

    for {_wire, key, managed, user} <- paths.fields do
      for {method, params} <- [
            {"config/value/write", edit.(key, user)},
            {"config/batchWrite",
             %{
               "edits" => [
                 edit.("desktop.appearanceTheme", "dark"),
                 edit.(key, managed)
               ]
             }}
          ] do
        error = upstream_error(pid, method, params)
        assert error["code"] == -32_600
        assert error["data"] === %{"config_write_error_code" => "configRequirementReadonly"}
        assert error["message"] === "`#{key}` is managed by requirements and cannot be changed"
        assert assert_managed_paths(pid, paths) === baseline
        refute get_in(call(pid, "config/read", %{}), ["config", "desktop", "appearanceTheme"])
        assert_path_sources(ctx, paths)
      end

      malformed =
        String.replace(
          paths.requirements,
          "#{key} = #{JSON.encode!(managed)}\n",
          "#{key} = 17\n",
          global: false
        )

      refute malformed === paths.requirements

      try do
        # The parent owns this synthetic source; the child mount remains read-only.
        File.write!(ctx.requirements, malformed)
        error = upstream_error(pid, "configRequirements/read", nil)
        assert error["code"] == -32_603
        assert error["message"] =~ "failed to read configuration layers:"
        assert error["message"] =~ "failed to parse requirements layer"
        assert error["message"] =~ "/etc/codex/requirements.toml"
        assert error["message"] =~ key
        assert Session.status(pid).phase == :ready
        assert Session.status(pid).pending == 0
        assert Session.status(pid).interactions == 0

        for {path, bytes} <- paths.sources, path != ctx.requirements do
          assert File.lstat!(path).type == :regular
          assert File.read!(path) === bytes
        end
      after
        File.write!(ctx.requirements, paths.requirements)
      end

      assert assert_managed_paths(pid, paths) === baseline
      assert_path_sources(ctx, paths)
      assert_idle(pid)
    end

    close(ctx, pid)
  end

  defp managed_paths(ctx) do
    for dir <- ~w(managed-state managed-logs user-state user-logs),
        do: File.mkdir_p!(Path.join(ctx.root, dir))

    managed_catalog = Path.join(ctx.root, "managed-models.json")
    user_catalog = Path.join(ctx.root, "user-models.json")

    for {path, slug} <- [{managed_catalog, "mock-model"}, {user_catalog, "unused-user-model"}] do
      File.write!(
        path,
        JSON.encode!(%{
          "models" => [
            %{
              "slug" => slug,
              "display_name" => "Synthetic path metadata only",
              "supported_reasoning_levels" => [],
              "shell_type" => "unified_exec",
              "visibility" => "list",
              "supported_in_api" => true,
              "priority" => 1,
              "model_messages" => %{"instructions_template" => "No execution in this profile."},
              "support_verbosity" => false,
              "truncation_policy" => %{"mode" => "bytes", "limit" => 10_000},
              "experimental_supported_tools" => []
            }
          ]
        })
      )
    end

    fields = [
      {"modelCatalogJson", "model_catalog_json", managed_catalog, user_catalog},
      {"logDir", "log_dir", Path.join(ctx.root, "managed-logs"),
       Path.join(ctx.root, "user-logs")},
      {"sqliteHome", "sqlite_home", Path.join(ctx.root, "managed-state"),
       Path.join(ctx.root, "user-state")}
    ]

    managed =
      Enum.map_join(fields, fn {_, key, path, _} -> "#{key} = #{JSON.encode!(path)}\n" end)

    user = Enum.map_join(fields, fn {_, key, _, path} -> "#{key} = #{JSON.encode!(path)}\n" end)
    requirements = managed <> @requirements
    File.write!(ctx.requirements, requirements)
    File.write!(ctx.config, user <> File.read!(ctx.config))

    for {_, key, _, path} <- fields,
        do: assert(File.read!(ctx.config) =~ "#{key} = #{JSON.encode!(path)}\n")

    sources =
      for path <- [ctx.config, ctx.requirements, managed_catalog, user_catalog],
          do: {path, File.read!(path)}

    %{fields: fields, sources: sources, requirements: requirements}
  end

  defp assert_managed_paths(pid, paths) do
    response = call(pid, "configRequirements/read", nil)
    requirements = Map.fetch!(response, "requirements")
    read = call(pid, "config/read", %{})
    effective = Map.fetch!(read, "config")
    origins = Map.fetch!(read, "origins")

    for {wire, key, expected, _} <- paths.fields do
      # Public requirements use PathUri; the effective ConfigToml retains paths.
      # These owned ASCII absolute paths have an independently prescribed URI.
      assert Map.fetch!(requirements, wire) === "file://" <> expected
      assert Map.fetch!(effective, key) === expected
      refute Map.has_key?(origins, key)
    end

    response
  end

  defp assert_path_sources(ctx, paths) do
    for {path, bytes} <- paths.sources do
      assert File.lstat!(path).type == :regular
      assert File.read!(path) === bytes
    end

    refute File.exists?(Path.join(ctx.root, "codex/auth.json"))
  end

  defp start(ctx),
    do: ManagedRequirementsFixture.start(ctx, "owned_managed_requirements")
end
