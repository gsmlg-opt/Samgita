defmodule SamgitaCodexDriver.NativeManagedPermissionRequirementsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ManagedRequirementsFixture, Session}
  import SamgitaCodexDriver.TurnFixture, only: [call: 3, upstream_error: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @common """
  allow_browser_and_computer_use = false
  allow_appshots = false
  allow_remote_control = false
  allow_managed_hooks_only = true
  """
  @definitions """
  [permissions.owned-audit]
  extends = ":read-only"
  [permissions.owned-review]
  extends = ":read-only"
  """
  @initial @common <>
             """
             default_permissions = "owned-audit"
             [allowed_permission_profiles]
             owned-audit = true
             owned-review = false
             ":read-only" = true
             """ <> @definitions
  @changed @common <>
             """
             default_permissions = "owned-review"
             [allowed_permission_profiles]
             owned-audit = false
             owned-review = true
             ":read-only" = true
             """ <> @definitions
  @initial_map %{"owned-audit" => true, "owned-review" => false, ":read-only" => true}
  @changed_map %{"owned-audit" => false, "owned-review" => true, ":read-only" => true}

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
    config = Path.join(root, "codex/config.toml")
    File.write!(requirements, @initial)

    config_bytes = """
    model = "mock-model"
    model_provider = "fixture"
    approval_policy = "on-request"
    default_permissions = ":read-only"
    web_search = "disabled"
    cli_auth_credentials_store = "ephemeral"
    check_for_update_on_startup = false
    allow_login_shell = false
    chatgpt_base_url = "http://127.0.0.1:9"
    openai_base_url = "http://127.0.0.1:9/v1"
    [features]
    hooks = false
    apps = false
    plugins = false
    recommended_plugins = false
    shell_snapshot = false
    [model_providers.fixture]
    name = "Nonexecuting managed permission metadata fixture"
    base_url = "http://127.0.0.1:9/v1"
    wire_api = "responses"
    requires_openai_auth = false
    supports_websockets = false
    request_max_retries = 0
    stream_max_retries = 0
    """

    File.write!(config, config_bytes)

    %{
      root: root,
      binary: Path.expand(binary),
      requirements: requirements,
      config: config,
      config_bytes: config_bytes
    }
  end

  test "named permission requirements reload remove restore and survive owned cold restart",
       ctx do
    pid = start(ctx)
    assert_policy(ctx, pid, @initial, @initial_map, "owned-audit")
    assert_user_selection(ctx, pid)

    File.write!(ctx.requirements, @changed)
    assert_policy(ctx, pid, @changed, @changed_map, "owned-review")
    assert_policy(ctx, pid, @changed, @changed_map, "owned-review")
    assert_user_selection(ctx, pid)

    File.write!(ctx.requirements, @common)
    assert_policy(ctx, pid, @common, nil, nil)
    assert_user_selection(ctx, pid)

    File.write!(ctx.requirements, @changed)
    assert_policy(ctx, pid, @changed, @changed_map, "owned-review")
    old_native = proof(ctx)["native_pid"]
    ManagedRequirementsFixture.close(ctx, pid)
    restarted = start(ctx)
    refute proof(ctx)["native_pid"] == old_native
    assert_policy(ctx, restarted, @changed, @changed_map, "owned-review")
    assert_user_selection(ctx, restarted)
    ManagedRequirementsFixture.close(ctx, restarted)
  end

  test "typed policy errors recover while a denied default is reported before full config rejects it",
       ctx do
    pid = start(ctx)
    baseline = assert_policy(ctx, pid, @initial, @initial_map, "owned-audit")
    assert_user_selection(ctx, pid)

    malformed_allowlist =
      String.replace(@initial, "owned-audit = true\n", "owned-audit = \"true\"\n", global: false)

    malformed_default =
      String.replace(
        @initial,
        "default_permissions = \"owned-audit\"\n",
        "default_permissions = 17\n",
        global: false
      )

    for {key, source} <- [
          {"allowed_permission_profiles", malformed_allowlist},
          {"default_permissions", malformed_default}
        ] do
      refute source === @initial

      try do
        File.write!(ctx.requirements, source)
        error = upstream_error(pid, "configRequirements/read", nil)
        assert error["code"] == -32_603
        assert error["message"] =~ "failed to read configuration layers:"
        assert error["message"] =~ "failed to parse requirements layer"
        assert error["message"] =~ "/etc/codex/requirements.toml"
        assert error["message"] =~ key
        assert Session.status(pid).phase == :ready
        assert Session.status(pid).pending == 0
        assert Session.status(pid).interactions == 0
        assert_sources(ctx, source)
      after
        File.write!(ctx.requirements, @initial)
      end

      assert assert_policy(ctx, pid, @initial, @initial_map, "owned-audit") === baseline
      assert_user_selection(ctx, pid)
    end

    denied_default =
      String.replace(
        @initial,
        "default_permissions = \"owned-audit\"\n",
        "default_permissions = \"owned-review\"\n",
        global: false
      )

    refute denied_default === @initial

    try do
      File.write!(ctx.requirements, denied_default)
      assert_policy(ctx, pid, denied_default, @initial_map, "owned-review")
      error = upstream_error(pid, "config/read", %{})
      assert error["code"] == -32_603
      assert error["message"] =~ "failed to resolve feature override precedence:"

      assert error["message"] =~
               "requirements.toml default_permissions `owned-review` must be allowed by allowed_permission_profiles"

      # Parsed policy reporting and full configuration validation are distinct.
      assert_policy(ctx, pid, denied_default, @initial_map, "owned-review")
    after
      File.write!(ctx.requirements, @initial)
    end

    assert assert_policy(ctx, pid, @initial, @initial_map, "owned-audit") === baseline
    assert_user_selection(ctx, pid)
    ManagedRequirementsFixture.close(ctx, pid)
  end

  defp assert_policy(ctx, pid, source, expected_map, expected_default) do
    response = call(pid, "configRequirements/read", nil)
    requirements = Map.fetch!(response, "requirements")
    assert Map.fetch!(requirements, "allowedPermissionProfiles") === expected_map
    assert Map.fetch!(requirements, "defaultPermissions") === expected_default
    assert_sources(ctx, source)
    ManagedRequirementsFixture.assert_idle(pid)
    assert Session.uncertain_operations(pid) === []
    response
  end

  defp assert_user_selection(ctx, pid) do
    # Managed defaultPermissions is a fallback, not an exact user-config overlay.
    config = call(pid, "config/read", %{}) |> Map.fetch!("config")
    assert Map.fetch!(config, "default_permissions") === ":read-only"
    assert File.read!(ctx.config) === ctx.config_bytes
    ManagedRequirementsFixture.assert_idle(pid)
    assert Session.uncertain_operations(pid) === []
  end

  defp assert_sources(ctx, source) do
    assert File.lstat!(ctx.requirements).type == :regular
    assert File.read!(ctx.requirements) === source
    assert File.lstat!(ctx.config).type == :regular
    assert File.read!(ctx.config) === ctx.config_bytes
    refute File.exists?(Path.join(ctx.root, "codex/auth.json"))
  end

  defp start(ctx), do: ManagedRequirementsFixture.start(ctx, "owned_permission_requirements")
  defp proof(ctx), do: ctx.root |> Path.join("proof.json") |> File.read!() |> JSON.decode!()
end
