defmodule SamgitaCodexDriver.NativeConfigAppsProjectionsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.ManagedRequirementsFixture
  import SamgitaCodexDriver.TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @requirements """
  allow_managed_hooks_only = true
  allow_browser_and_computer_use = false
  allow_appshots = false
  allow_remote_control = false
  check_for_update_on_startup = false
  allow_login_shell = false
  """
  @root_config """
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
  name = "Nonexecuting app policy metadata fixture"
  base_url = "http://127.0.0.1:9/v1"
  wire_api = "responses"
  requires_openai_auth = false
  supports_websockets = false
  request_max_retries = 0
  stream_max_retries = 0
  """
  @empty_app %{
    "enabled" => true,
    "omit_tools_from" => nil,
    "approvals_reviewer" => nil,
    "destructive_enabled" => nil,
    "open_world_enabled" => nil,
    "default_tools_approval_mode" => nil,
    "default_tools_enabled" => nil,
    "tools" => nil,
    "links" => nil
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
    File.write!(requirements, @requirements)

    %{
      binary: Path.expand(binary),
      root: root,
      config: Path.join(root, "codex/config.toml"),
      requirements: requirements
    }
  end

  test "absent app policy is a present native null", ctx do
    assert read_apps(ctx) === nil
  end

  test "an empty apps table retains a present null default", ctx do
    assert read_apps(ctx, "[apps]\n") === %{"_default" => nil}
  end

  test "empty nested policies preserve true defaults and distinguish null empty and typed maps",
       ctx do
    apps =
      read_apps(ctx, """
      [apps._default]
      [apps.owned_empty]
      [apps.owned_nested]
      [apps.owned_nested.tools."repos/list"]
      [apps.owned_nested.links.link_work]
      [apps.owned_containers.tools]
      [apps.owned_containers.links]
      """)

    assert apps === %{
             "_default" => %{
               "enabled" => true,
               "approvals_reviewer" => nil,
               "destructive_enabled" => true,
               "open_world_enabled" => true,
               "default_tools_approval_mode" => nil
             },
             "owned_empty" => @empty_app,
             "owned_nested" =>
               Map.merge(@empty_app, %{
                 "tools" => %{"repos/list" => %{"enabled" => nil, "approval_mode" => nil}},
                 "links" => %{
                   "link_work" => %{
                     "approvals_reviewer" => nil,
                     "default_tools_approval_mode" => nil
                   }
                 }
               }),
             "owned_containers" => Map.merge(@empty_app, %{"tools" => %{}, "links" => %{}})
           }
  end

  test "explicit app tool and link metadata retains distinct controls without expanding inheritance",
       ctx do
    apps =
      read_apps(ctx, """
      [apps._default]
      enabled = false
      approvals_reviewer = "auto_review"
      destructive_enabled = false
      open_world_enabled = false
      default_tools_approval_mode = "writes"
      [apps.owned_alpha]
      enabled = false
      omit_tools_from = ["deferred"]
      approvals_reviewer = "user"
      destructive_enabled = false
      open_world_enabled = true
      default_tools_approval_mode = "prompt"
      default_tools_enabled = false
      [apps.owned_alpha.tools."repos/list"]
      enabled = true
      approval_mode = "approve"
      [apps.owned_alpha.links.link_work]
      approvals_reviewer = "auto_review"
      default_tools_approval_mode = "writes"
      [apps.owned_control]
      omit_tools_from = []
      """)

    assert apps === %{
             "_default" => %{
               "enabled" => false,
               "approvals_reviewer" => "auto_review",
               "destructive_enabled" => false,
               "open_world_enabled" => false,
               "default_tools_approval_mode" => "writes"
             },
             "owned_alpha" => %{
               "enabled" => false,
               "omit_tools_from" => ["deferred"],
               "approvals_reviewer" => "user",
               "destructive_enabled" => false,
               "open_world_enabled" => true,
               "default_tools_approval_mode" => "prompt",
               "default_tools_enabled" => false,
               "tools" => %{"repos/list" => %{"enabled" => true, "approval_mode" => "approve"}},
               "links" => %{
                 "link_work" => %{
                   "approvals_reviewer" => "auto_review",
                   "default_tools_approval_mode" => "writes"
                 }
               }
             },
             "owned_control" => Map.put(@empty_app, "omit_tools_from", [])
           }
  end

  defp read_apps(ctx, tables \\ "") do
    input = @root_config <> tables
    File.write!(ctx.config, input)
    pid = ManagedRequirementsFixture.start(ctx, "owned_config_apps_projections")
    response = call(pid, "config/read", %{})
    assert File.read!(ctx.config) === input
    assert File.read!(ctx.requirements) === @requirements
    config = Map.fetch!(response, "config")
    assert Map.fetch!(config, "web_search") === "disabled"

    for key <- ~w(apps plugins recommended_plugins) do
      assert Map.fetch!(Map.fetch!(config, "features"), key) === false
    end

    apps = Map.fetch!(config, "apps")
    ManagedRequirementsFixture.assert_idle(pid)
    ManagedRequirementsFixture.close(ctx, pid)
    apps
  end
end
