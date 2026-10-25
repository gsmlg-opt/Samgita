defmodule SamgitaCodexDriver.NativeManagedComputerRequirementsTest do
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
  @computer """
  [computer_use]
  allow_locked_computer_use = false
  allow_persistent_approval = false
  default_app_access = "deny"
  [computer_use.macos.bundle_ids]
  "com.owned.synthetic-a" = "deny"
  "com.owned.synthetic-b" = "deny"
  [computer_use.windows.aumids]
  "Owned.SyntheticA!App" = "deny"
  "Owned.SyntheticB!App" = "deny"
  [[computer_use.windows.exes]]
  publisher_name = "Owned Synthetic Publisher A"
  product_name = "Owned Synthetic Product A"
  binary_name = "owned-synthetic-a.exe"
  access = "deny"
  [[computer_use.windows.exes]]
  publisher_name = "Owned Synthetic Publisher B"
  product_name = "Owned Synthetic Product B"
  access = "deny"
  """
  @source @common <> @computer
  @expected %{
    "allowLockedComputerUse" => false,
    "allowPersistentApproval" => false,
    "defaultAppAccess" => "deny",
    "macos" => %{
      "bundleIds" => %{"com.owned.synthetic-a" => "deny", "com.owned.synthetic-b" => "deny"}
    },
    "windows" => %{
      "aumids" => %{"Owned.SyntheticA!App" => "deny", "Owned.SyntheticB!App" => "deny"},
      "exes" => [
        %{
          "publisherName" => "Owned Synthetic Publisher A",
          "productName" => "Owned Synthetic Product A",
          "binaryName" => "owned-synthetic-a.exe",
          "access" => "deny"
        },
        %{
          "publisherName" => "Owned Synthetic Publisher B",
          "productName" => "Owned Synthetic Product B",
          "binaryName" => nil,
          "access" => "deny"
        }
      ]
    }
  }

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
    File.write!(requirements, @source)

    config_bytes = """
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
    hooks = false
    apps = false
    plugins = false
    recommended_plugins = false
    shell_snapshot = false
    browser_use = false
    browser_use_full_cdp_access = false
    browser_use_external = false
    computer_use = false
    [model_providers.fixture]
    name = "Nonexecuting computer requirement metadata fixture"
    base_url = "http://127.0.0.1:9/v1"
    wire_api = "responses"
    requires_openai_auth = false
    supports_websockets = false
    request_max_retries = 0
    stream_max_retries = 0
    """

    File.write!(config, config_bytes)

    %{
      binary: Path.expand(binary),
      root: root,
      requirements: requirements,
      config: config,
      config_bytes: config_bytes
    }
  end

  test "native Linux reads typed macos and Windows requirement metadata across removal and restart",
       ctx do
    pid = start(ctx)
    original_native = proof(ctx)["native_pid"]
    assert read(ctx, pid, @source) === @expected

    File.write!(ctx.requirements, @common)
    assert read(ctx, pid, @common) === nil
    File.write!(ctx.requirements, @source)
    assert read(ctx, pid, @source) === @expected
    ManagedRequirementsFixture.close(ctx, pid)
    assert_sources(ctx, @source)

    cold = start(ctx)
    refute proof(ctx)["native_pid"] == original_native
    assert read(ctx, cold, @source) === @expected
    ManagedRequirementsFixture.close(ctx, cold)
    assert_sources(ctx, @source)
  end

  test "absent per-OS policy tables stay distinct from present empty tables", ctx do
    pid = start(ctx)
    minimal = @common <> "[computer_use]\nallow_locked_computer_use = false\n"

    bare = %{
      "allowLockedComputerUse" => false,
      "allowPersistentApproval" => nil,
      "defaultAppAccess" => nil,
      "macos" => nil,
      "windows" => nil
    }

    File.write!(ctx.requirements, minimal)
    assert read(ctx, pid, minimal) === bare
    empty = minimal <> "[computer_use.macos]\n[computer_use.windows]\n"
    File.write!(ctx.requirements, empty)

    assert read(ctx, pid, empty) ===
             Map.merge(bare, %{
               "macos" => %{"bundleIds" => nil},
               "windows" => %{"aumids" => nil, "exes" => nil}
             })

    File.write!(ctx.requirements, @source)
    assert read(ctx, pid, @source) === @expected
    ManagedRequirementsFixture.close(ctx, pid)
    assert_sources(ctx, @source)
  end

  test "malformed managed computer maps and executable rows reject without changing user files",
       ctx do
    pid = start(ctx)
    assert read(ctx, pid, @source) === @expected

    invalid = [
      {"\"com.owned.synthetic-a\" = \"deny\"", "\"com.owned.synthetic-a\" = 17"},
      {"\"Owned.SyntheticA!App\" = \"deny\"", "\"Owned.SyntheticA!App\" = 17"},
      {"binary_name = \"owned-synthetic-a.exe\"", "binary_name = 17"},
      {"publisher_name = \"Owned Synthetic Publisher A\"", "publisher_name = 17"}
    ]

    for {valid, invalid} <- invalid do
      assert length(:binary.matches(@source, valid)) == 1
      source = String.replace(@source, valid, invalid, global: false)
      refute source === @source

      try do
        File.write!(ctx.requirements, source)
        error = upstream_error(pid, "configRequirements/read", nil)
        assert error["code"] == -32_603
        assert error["message"] =~ "failed to read configuration layers:"
        assert error["message"] =~ "failed to parse requirements layer"
        assert error["message"] =~ "/etc/codex/requirements.toml"
        assert_idle(ctx, pid, source)
      after
        File.write!(ctx.requirements, @source)
        assert_sources(ctx, @source)
      end

      assert read(ctx, pid, @source) === @expected
    end

    ManagedRequirementsFixture.close(ctx, pid)
    assert_sources(ctx, @source)
  end

  defp read(ctx, pid, source) do
    response = call(pid, "configRequirements/read", nil)
    requirements = Map.fetch!(response, "requirements")
    assert Map.fetch!(requirements, "allowBrowserAndComputerUse") === false
    computer = Map.fetch!(requirements, "computerUse")
    assert_idle(ctx, pid, source)
    computer
  end

  defp assert_idle(ctx, pid, source) do
    assert_sources(ctx, source)
    ManagedRequirementsFixture.assert_idle(pid)
    assert Session.uncertain_operations(pid) === []
    assert_sources(ctx, source)
  end

  defp assert_sources(ctx, source) do
    assert File.read!(ctx.requirements) === source
    assert File.read!(ctx.config) === ctx.config_bytes
    refute File.exists?(Path.join(ctx.root, "codex/auth.json"))
    workspace = Path.join(ctx.root, "workspace")
    assert File.ls!(workspace) === [".git"]
    assert File.ls!(Path.join(workspace, ".git")) === ["HEAD"]

    assert File.read!(Path.join(workspace, ".git/HEAD")) ===
             "ref: refs/heads/samgita-managed-fixture\n"
  end

  defp start(ctx),
    do: ManagedRequirementsFixture.start(ctx, "owned_computer_requirement_metadata")

  defp proof(ctx), do: ctx.root |> Path.join("proof.json") |> File.read!() |> JSON.decode!()
end
