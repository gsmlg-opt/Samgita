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

  defp start(ctx),
    do: ManagedRequirementsFixture.start(ctx, "owned_managed_requirements")
end
