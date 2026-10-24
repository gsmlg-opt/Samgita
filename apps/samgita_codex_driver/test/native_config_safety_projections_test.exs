defmodule SamgitaCodexDriver.NativeConfigSafetyProjectionsTest do
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
  browser_use = false
  browser_use_full_cdp_access = false
  browser_use_external = false
  computer_use = false
  web_search_request = false
  web_search_cached = false
  [model_providers.fixture]
  name = "Nonexecuting safety metadata fixture"
  base_url = "http://127.0.0.1:9/v1"
  wire_api = "responses"
  requires_openai_auth = false
  supports_websockets = false
  request_max_retries = 0
  stream_max_retries = 0
  """
  @null_policy %{
    "access" => nil,
    "downloads" => nil,
    "uploads" => nil,
    "full_cdp_access" => nil
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

  test "absent source safety and tool tables become explicit native nulls", ctx do
    config = read(ctx)

    for field <- ~w(browser_use computer_use tools),
        do: assert(Map.fetch!(config, field) === nil)
  end

  test "empty top-level tables keep absent nested policies explicitly null", ctx do
    config = read(ctx, "[browser_use]\n[computer_use]\n[tools]\n")

    assert config["browser_use"] === %{
             "allow_history_access" => nil,
             "default_origin_policy" => nil,
             "origins" => nil
           }

    assert config["computer_use"] === %{
             "default_app_access" => nil,
             "macos" => nil,
             "windows" => nil
           }

    assert config["tools"] === %{"web_search" => nil}
  end

  test "empty web search metadata table retains absent location and options as null", ctx do
    config = read(ctx, "[tools.web_search]\n")

    assert config["tools"] === %{
             "web_search" => %{
               "context_size" => nil,
               "allowed_domains" => nil,
               "location" => nil
             }
           }
  end

  test "empty nested policies platforms and location retain exact parsed defaults", ctx do
    config =
      read(ctx, """
      [browser_use.default_origin_policy]
      [browser_use.origins."https://empty.invalid"]
      [computer_use.macos]
      [computer_use.windows]
      [tools.web_search.location]
      """)

    assert config["browser_use"] === %{
             "allow_history_access" => nil,
             "default_origin_policy" => @null_policy,
             "origins" => %{"https://empty.invalid" => @null_policy}
           }

    assert config["computer_use"] === %{
             "default_app_access" => nil,
             "macos" => %{"bundle_ids" => nil},
             "windows" => %{"aumids" => nil, "exes" => nil}
           }

    assert config["tools"] === %{
             "web_search" => %{
               "context_size" => nil,
               "allowed_domains" => nil,
               "location" => %{
                 "country" => nil,
                 "region" => nil,
                 "city" => nil,
                 "timezone" => nil
               }
             }
           }
  end

  test "first explicit metadata policy preserves values without enabling capabilities", ctx do
    config =
      read(ctx, """
      [browser_use]
      allow_history_access = false
      [browser_use.default_origin_policy]
      access = "deny"
      downloads = "allow"
      uploads = "deny"
      full_cdp_access = "deny"
      [browser_use.origins."https://policy-a.invalid"]
      access = "allow"
      [computer_use]
      default_app_access = "deny"
      [computer_use.macos.bundle_ids]
      "invalid.synthetic.a" = "deny"
      [computer_use.windows.aumids]
      "Synthetic.A!Fixture" = "allow"
      [[computer_use.windows.exes]]
      publisher_name = "Synthetic Publisher A"
      product_name = "Synthetic Product A"
      access = "deny"
      [tools.web_search]
      context_size = "low"
      allowed_domains = []
      [tools.web_search.location]
      country = "US"
      region = "California"
      city = "Synthetic A"
      timezone = "America/Los_Angeles"
      """)

    assert config["browser_use"] === %{
             "allow_history_access" => false,
             "default_origin_policy" => policy("deny", "allow", "deny", "deny"),
             "origins" => %{"https://policy-a.invalid" => %{@null_policy | "access" => "allow"}}
           }

    assert config["computer_use"] === %{
             "default_app_access" => "deny",
             "macos" => %{"bundle_ids" => %{"invalid.synthetic.a" => "deny"}},
             "windows" => %{
               "aumids" => %{"Synthetic.A!Fixture" => "allow"},
               "exes" => [
                 %{
                   "publisher_name" => "Synthetic Publisher A",
                   "product_name" => "Synthetic Product A",
                   "binary_name" => nil,
                   "access" => "deny"
                 }
               ]
             }
           }

    assert config["tools"] === %{
             "web_search" => %{
               "context_size" => "low",
               "allowed_domains" => [],
               "location" => %{
                 "country" => "US",
                 "region" => "California",
                 "city" => "Synthetic A",
                 "timezone" => "America/Los_Angeles"
               }
             }
           }
  end

  test "distinct explicit metadata policy changes each nested field independently", ctx do
    config =
      read(ctx, """
      [browser_use]
      allow_history_access = true
      [browser_use.default_origin_policy]
      access = "allow"
      downloads = "deny"
      uploads = "allow"
      full_cdp_access = "allow"
      [browser_use.origins."https://policy-b.invalid"]
      access = "deny"
      downloads = "deny"
      uploads = "allow"
      full_cdp_access = "allow"
      [computer_use]
      default_app_access = "allow"
      [computer_use.macos.bundle_ids]
      "invalid.synthetic.b" = "allow"
      [computer_use.windows.aumids]
      "Synthetic.B!Fixture" = "deny"
      [[computer_use.windows.exes]]
      publisher_name = "Synthetic Publisher B"
      product_name = "Synthetic Product B"
      binary_name = "synthetic-never-executed.exe"
      access = "allow"
      [tools.web_search]
      context_size = "high"
      allowed_domains = ["policy-b.invalid", "second-b.invalid"]
      [tools.web_search.location]
      country = "JP"
      region = "Tokyo"
      city = "Synthetic B"
      timezone = "Asia/Tokyo"
      """)

    assert config["browser_use"] === %{
             "allow_history_access" => true,
             "default_origin_policy" => policy("allow", "deny", "allow", "allow"),
             "origins" => %{
               "https://policy-b.invalid" => policy("deny", "deny", "allow", "allow")
             }
           }

    assert config["computer_use"] === %{
             "default_app_access" => "allow",
             "macos" => %{"bundle_ids" => %{"invalid.synthetic.b" => "allow"}},
             "windows" => %{
               "aumids" => %{"Synthetic.B!Fixture" => "deny"},
               "exes" => [
                 %{
                   "publisher_name" => "Synthetic Publisher B",
                   "product_name" => "Synthetic Product B",
                   "binary_name" => "synthetic-never-executed.exe",
                   "access" => "allow"
                 }
               ]
             }
           }

    assert config["tools"] === %{
             "web_search" => %{
               "context_size" => "high",
               "allowed_domains" => ["policy-b.invalid", "second-b.invalid"],
               "location" => %{
                 "country" => "JP",
                 "region" => "Tokyo",
                 "city" => "Synthetic B",
                 "timezone" => "Asia/Tokyo"
               }
             }
           }
  end

  defp read(ctx, tables \\ "") do
    input = @root_config <> tables
    File.write!(ctx.config, input)
    pid = ManagedRequirementsFixture.start(ctx, "owned_config_safety_projections")
    response = call(pid, "config/read", %{})
    assert File.read!(ctx.config) === input
    assert File.read!(ctx.requirements) === @requirements
    config = Map.fetch!(response, "config")
    assert Map.fetch!(config, "web_search") === "disabled"

    for key <- ~w(browser_use browser_use_full_cdp_access browser_use_external computer_use
                   web_search_request web_search_cached) do
      assert Map.fetch!(Map.fetch!(config, "features"), key) === false
    end

    ManagedRequirementsFixture.assert_idle(pid)
    ManagedRequirementsFixture.close(ctx, pid)
    config
  end

  defp policy(access, downloads, uploads, full_cdp_access) do
    %{
      "access" => access,
      "downloads" => downloads,
      "uploads" => uploads,
      "full_cdp_access" => full_cdp_access
    }
  end
end
