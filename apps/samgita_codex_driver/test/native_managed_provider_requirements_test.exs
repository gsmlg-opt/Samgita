defmodule SamgitaCodexDriver.NativeManagedProviderRequirementsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ManagedRequirementsFixture, TurnFixture}
  import ManagedRequirementsFixture, only: [close: 2, assert_idle: 1]
  import TurnFixture, only: [call: 3, upstream_error: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/managed_requirements_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @chatgpt_url "http://127.0.0.1:9/managed-chatgpt"
  @managed_provider %{
    "name" => "Managed nonexecuting provider",
    "base_url" => "http://127.0.0.1:9/managed/v1",
    "wire_api" => "responses",
    "requires_openai_auth" => false,
    "supports_websockets" => false,
    "request_max_retries" => 0,
    "stream_max_retries" => 0
  }
  @requirements """
  cli_auth_credentials_store = "ephemeral"
  chatgpt_base_url = "#{@chatgpt_url}"
  [model_providers.fixture]
  name = "Managed nonexecuting provider"
  base_url = "http://127.0.0.1:9/managed/v1"
  wire_api = "responses"
  requires_openai_auth = false
  supports_websockets = false
  request_max_retries = 0
  stream_max_retries = 0
  """

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha
    assert File.regular?(@script), "BLOCKED_ENV: integrate Config4 managed policy fixture first"

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
    chatgpt_base_url = "http://127.0.0.1:9/user-chatgpt"
    openai_base_url = "http://127.0.0.1:9/v1"
    check_for_update_on_startup = false
    allow_login_shell = false
    [features]
    apps = false
    plugins = false
    recommended_plugins = false
    shell_snapshot = false
    [model_providers.fixture]
    name = "User nonexecuting provider"
    base_url = "http://127.0.0.1:9/user/v1"
    wire_api = "responses"
    requires_openai_auth = false
    supports_websockets = false
    request_max_retries = 0
    stream_max_retries = 0
    [model_providers.other_fixture]
    name = "Unselected nonexecuting provider"
    base_url = "http://127.0.0.1:9/other/v1"
    wire_api = "responses"
    requires_openai_auth = false
    supports_websockets = false
    request_max_retries = 0
    stream_max_retries = 0
    """)

    %{binary: Path.expand(binary), root: root, config: config, requirements: requirements}
  end

  test "managed provider definitions overlay user values without persisting the overlay", ctx do
    before = File.read!(ctx.config)
    pid = start(ctx)
    requirements = call(pid, "configRequirements/read", nil)["requirements"]
    providers = requirements["modelProviders"]
    assert Map.keys(providers) == ["fixture"]
    assert Map.take(providers["fixture"], Map.keys(@managed_provider)) === @managed_provider
    assert requirements["cliAuthCredentialsStore"] === "ephemeral"
    assert requirements["chatgptBaseUrl"] === @chatgpt_url

    read = call(pid, "config/read", %{})
    assert read["config"]["model_providers"]["fixture"] === providers["fixture"]

    assert read["config"]["model_providers"]["other_fixture"]["name"] ==
             "Unselected nonexecuting provider"

    assert read["config"]["cli_auth_credentials_store"] === "ephemeral"
    assert read["config"]["chatgpt_base_url"] === @chatgpt_url
    refute Map.has_key?(read["origins"], "model_providers.fixture.name")
    refute Map.has_key?(read["origins"], "cli_auth_credentials_store")
    refute Map.has_key?(read["origins"], "chatgpt_base_url")
    assert File.read!(ctx.config) === before
    assert File.read!(ctx.config) =~ "User nonexecuting provider"
    assert File.read!(ctx.requirements) === @requirements
    assert_idle(pid)
    close(ctx, pid)
  end

  test "managed provider descendant and ancestor writes are both readonly", ctx do
    pid = start(ctx)
    before = File.read!(ctx.config)
    requirements = call(pid, "configRequirements/read", nil)

    for {path, value} <- [
          {"model_providers.fixture.name", "Rejected metadata change"},
          {"model_providers", %{}}
        ] do
      error = upstream_error(pid, "config/value/write", edit(path, value))
      assert_managed_error(error, "model_providers")
      assert File.read!(ctx.config) === before
      assert call(pid, "configRequirements/read", nil) === requirements
    end

    assert_idle(pid)
    close(ctx, pid)
  end

  test "managed auth and loopback URL reject whole batches including safe no-op edits", ctx do
    pid = start(ctx)
    before = File.read!(ctx.config)
    requirements = call(pid, "configRequirements/read", nil)

    for {path, value} <- [
          {"cli_auth_credentials_store", "ephemeral"},
          {"chatgpt_base_url", @chatgpt_url}
        ] do
      error =
        upstream_error(pid, "config/batchWrite", %{
          "edits" => [edit("desktop.appearanceTheme", "dark"), edit(path, value)]
        })

      assert_managed_error(error, path)
      assert File.read!(ctx.config) === before
      assert call(pid, "configRequirements/read", nil) === requirements
      refute get_in(call(pid, "config/read", %{}), ["config", "desktop", "appearanceTheme"])
    end

    assert_idle(pid)
    close(ctx, pid)
  end

  test "unmanaged provider metadata stays writable and survives restart beside the managed provider",
       ctx do
    pid = start(ctx)
    requirements = call(pid, "configRequirements/read", nil)

    result =
      call(
        pid,
        "config/value/write",
        edit("model_providers.other_fixture.name", "Updated unselected metadata")
      )

    assert result["status"] == "ok"
    assert result["filePath"] == ctx.config
    assert is_binary(result["version"])
    persisted = File.read!(ctx.config)
    assert persisted =~ "Updated unselected metadata"
    assert persisted =~ "User nonexecuting provider"
    assert call(pid, "configRequirements/read", nil) === requirements
    assert_effective_providers(pid, requirements)
    assert_idle(pid)
    close(ctx, pid)

    restarted = start(ctx)
    assert File.read!(ctx.config) === persisted
    assert call(restarted, "configRequirements/read", nil) === requirements
    assert_effective_providers(restarted, requirements)
    assert File.read!(ctx.requirements) === @requirements
    assert_idle(restarted)
    close(ctx, restarted)
  end

  defp assert_effective_providers(pid, requirements) do
    providers = call(pid, "config/read", %{})["config"]["model_providers"]
    assert providers["fixture"] === requirements["requirements"]["modelProviders"]["fixture"]
    assert providers["other_fixture"]["name"] === "Updated unselected metadata"
    assert providers["other_fixture"]["base_url"] === "http://127.0.0.1:9/other/v1"
    assert providers["other_fixture"]["requires_openai_auth"] === false
  end

  defp edit(path, value), do: %{"keyPath" => path, "value" => value, "mergeStrategy" => "replace"}

  defp assert_managed_error(error, field) do
    assert error["code"] == -32_600
    assert error["data"] === %{"config_write_error_code" => "configRequirementReadonly"}
    assert error["message"] === "`#{field}` is managed by requirements and cannot be changed"
  end

  defp start(ctx),
    do: ManagedRequirementsFixture.start(ctx, "owned_managed_provider_requirements")
end
