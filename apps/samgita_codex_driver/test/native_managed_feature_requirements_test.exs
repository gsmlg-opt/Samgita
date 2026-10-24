defmodule SamgitaCodexDriver.NativeManagedFeatureRequirementsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ManagedRequirementsFixture, Session, TurnFixture}
  import ManagedRequirementsFixture, only: [close: 2, assert_idle: 1]
  import TurnFixture, only: [call: 3, upstream_error: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @origin_policy %{
    "access" => "deny",
    "downloads" => "deny",
    "uploads" => "deny",
    "fullCdpAccess" => "deny",
    "autoReview" => "deny",
    "persistentApproval" => false,
    "accessApprovalLifetime" => "turn"
  }
  @requirements """
  allow_browser_and_computer_use = false
  allow_appshots = false
  allow_remote_control = false
  [browser_use]
  allow_webmcp = false
  allow_history_access = false
  disable_auto_review = true
  allow_global_persistent_approval = false
  [browser_use.default_origin_policy]
  access = "deny"
  downloads = "deny"
  uploads = "deny"
  full_cdp_access = "deny"
  auto_review = "deny"
  persistent_approval = false
  access_approval_lifetime = "turn"
  [computer_use]
  allow_locked_computer_use = false
  allow_persistent_approval = false
  default_app_access = "deny"
  [in_app_browser]
  allow_external_browser_settings_import = false
  [application.network]
  enabled = true
  [application.network.domains]
  "Owned.Invalid." = "deny"
  """
  @refreshed_requirements @requirements <>
                            ~s("SECOND.INVALID." = "deny"\n) <>
                            """
                            [browser_use.origins."https://additional.invalid"]
                            access = "deny"
                            downloads = "deny"
                            uploads = "deny"
                            full_cdp_access = "deny"
                            auto_review = "deny"
                            persistent_approval = false
                            access_approval_lifetime = "turn"
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
    chatgpt_base_url = "http://127.0.0.1:9"
    openai_base_url = "http://127.0.0.1:9/v1"
    check_for_update_on_startup = false
    allow_login_shell = false
    [features]
    apps = false
    plugins = false
    recommended_plugins = false
    shell_snapshot = false
    [model_providers.fixture]
    name = "Nonexecuting restrictive metadata fixture"
    base_url = "http://127.0.0.1:9/v1"
    wire_api = "responses"
    requires_openai_auth = false
    supports_websockets = false
    request_max_retries = 0
    stream_max_retries = 0
    """)

    %{binary: Path.expand(binary), root: root, config: config, requirements: requirements}
  end

  test "restrictive nested requirements retain typed browser computer and application metadata",
       ctx do
    before = File.read!(ctx.config)
    pid = start(ctx)
    response = call(pid, "configRequirements/read", nil)
    assert_profile(response["requirements"], %{"owned.invalid" => "deny"}, nil)
    assert File.read!(ctx.config) === before
    assert File.read!(ctx.requirements) === @requirements
    assert_idle(pid)
    close(ctx, pid)
  end

  test "explicit read reloads added deny metadata and returns native domain normalization", ctx do
    before = File.read!(ctx.config)
    pid = start(ctx)
    baseline = call(pid, "configRequirements/read", nil)
    File.write!(ctx.requirements, @refreshed_requirements)
    refreshed = call(pid, "configRequirements/read", nil)
    domains = %{"owned.invalid" => "deny", "second.invalid" => "deny"}
    origins = %{"https://additional.invalid" => @origin_policy}
    assert_profile(refreshed["requirements"], domains, origins)

    expected =
      baseline
      |> put_in(["requirements", "application", "network", "domains"], domains)
      |> put_in(["requirements", "browserUse", "origins"], origins)

    assert refreshed === expected
    assert File.read!(ctx.config) === before
    assert File.read!(ctx.requirements) === @refreshed_requirements
    assert_idle(pid)
    close(ctx, pid)
  end

  test "invalid nested lifetime and wildcard domain fail reads and repaired policy recovers",
       ctx do
    before = File.read!(ctx.config)
    pid = start(ctx)
    baseline = call(pid, "configRequirements/read", nil)

    invalid = [
      {String.replace(
         @requirements,
         "access_approval_lifetime = \"turn\"",
         "access_approval_lifetime = \"not-a-lifetime\""
       ), "unknown variant `not-a-lifetime`"},
      {String.replace(@requirements, "\"Owned.Invalid.\"", "\"*.owned.invalid\""),
       "application.network.domains requires exact ASCII domain names without URLs, ports, or wildcards"}
    ]

    for {requirements, diagnostic} <- invalid do
      try do
        File.write!(ctx.requirements, requirements)
        error = upstream_error(pid, "configRequirements/read", nil)
        assert error["code"] == -32_603
        assert error["message"] =~ "failed to read configuration layers:"
        assert error["message"] =~ "failed to parse requirements layer"
        assert error["message"] =~ "/etc/codex/requirements.toml"
        assert error["message"] =~ diagnostic
        assert Session.status(pid).phase == :ready
        assert File.read!(ctx.config) === before
      after
        File.write!(ctx.requirements, @requirements)
      end

      assert call(pid, "configRequirements/read", nil) === baseline
    end

    assert_idle(pid)
    close(ctx, pid)
  end

  test "cold restart reads refreshed restrictive source without persisting it to user config",
       ctx do
    before = File.read!(ctx.config)
    File.write!(ctx.requirements, @refreshed_requirements)
    pid = start(ctx)
    baseline = call(pid, "configRequirements/read", nil)
    domains = %{"owned.invalid" => "deny", "second.invalid" => "deny"}
    origins = %{"https://additional.invalid" => @origin_policy}
    assert_profile(baseline["requirements"], domains, origins)
    assert_idle(pid)
    close(ctx, pid)

    restarted = start(ctx)
    assert call(restarted, "configRequirements/read", nil) === baseline
    assert File.read!(ctx.config) === before
    assert File.read!(ctx.requirements) === @refreshed_requirements
    assert_idle(restarted)
    close(ctx, restarted)
  end

  defp assert_profile(requirements, domains, origins) do
    assert requirements["allowBrowserAndComputerUse"] === false
    browser = requirements["browserUse"]

    assert Map.take(browser, [
             "allowWebmcp",
             "allowHistoryAccess",
             "disableAutoReview",
             "allowGlobalPersistentApproval",
             "defaultOriginPolicy",
             "origins"
           ]) === %{
             "allowWebmcp" => false,
             "allowHistoryAccess" => false,
             "disableAutoReview" => true,
             "allowGlobalPersistentApproval" => false,
             "defaultOriginPolicy" => @origin_policy,
             "origins" => origins
           }

    assert Map.take(requirements["computerUse"], [
             "allowLockedComputerUse",
             "allowPersistentApproval",
             "defaultAppAccess"
           ]) === %{
             "allowLockedComputerUse" => false,
             "allowPersistentApproval" => false,
             "defaultAppAccess" => "deny"
           }

    assert requirements["inAppBrowser"] === %{"allowExternalBrowserSettingsImport" => false}

    assert requirements["application"] === %{
             "network" => %{"enabled" => true, "domains" => domains}
           }
  end

  defp start(ctx),
    do: ManagedRequirementsFixture.start(ctx, "owned_managed_feature_requirements")
end
