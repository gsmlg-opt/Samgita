defmodule SamgitaCodexDriver.NativeConfigOptionProjectionsTest do
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
  """
  # Remove only the two explicit selections before supplying alternatives.
  # approval_policy stays on-request; this is not an all-Config null fixture.
  @selection_root_config String.replace(
                           @root_config,
                           "sandbox_mode = \"read-only\"\nweb_search = \"disabled\"\n",
                           ""
                         )
  @tables """
  [features]
  apps = false
  plugins = false
  recommended_plugins = false
  shell_snapshot = false
  [model_providers.fixture]
  name = "Nonexecuting config projection fixture"
  base_url = "http://127.0.0.1:9/v1"
  wire_api = "responses"
  requires_openai_auth = false
  supports_websockets = false
  request_max_retries = 0
  stream_max_retries = 0
  """
  @optional_fields ~w(review_model model_context_window model_auto_compact_token_limit
                      instructions developer_instructions compact_prompt
                      model_reasoning_summary model_verbosity analytics sandbox_workspace_write)
  @profile_a %{
    "review_model" => "synthetic-owned-review-a",
    "model_context_window" => 8192,
    "model_auto_compact_token_limit" => 4096,
    "instructions" => "",
    "developer_instructions" => "Synthetic owned developer A",
    "compact_prompt" => "",
    "model_reasoning_summary" => "concise",
    "model_verbosity" => "low"
  }
  @profile_b %{
    "review_model" => "synthetic-owned-review-b",
    "model_context_window" => 12_288,
    "model_auto_compact_token_limit" => 6144,
    "instructions" => "Synthetic owned instructions B",
    "developer_instructions" => "",
    "compact_prompt" => "Synthetic owned compact B",
    "model_reasoning_summary" => "detailed",
    "model_verbosity" => "high"
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

  test "absent source options are present native nulls rather than missing members", ctx do
    config = read(ctx)

    for field <- @optional_fields do
      assert Map.fetch!(config, field) === nil
    end

    assert_projection(config, %{
      "approvals_reviewer" => nil,
      "forced_login_method" => nil,
      "forced_chatgpt_workspace_id" => nil,
      "model_auto_compact_token_limit_scope" => nil,
      "sandbox_mode" => "read-only",
      "web_search" => "disabled"
    })
  end

  test "first explicit scalar projection preserves empty strings and selected low verbosity",
       ctx do
    config =
      read(ctx, """
      review_model = "synthetic-owned-review-a"
      model_context_window = 8192
      model_auto_compact_token_limit = 4096
      instructions = ""
      developer_instructions = "Synthetic owned developer A"
      compact_prompt = ""
      model_reasoning_summary = "concise"
      model_verbosity = "low"
      """)

    assert_projection(config, @profile_a)
  end

  test "distinct explicit scalar projection preserves values without using a response oracle",
       ctx do
    config =
      read(ctx, """
      review_model = "synthetic-owned-review-b"
      model_context_window = 12288
      model_auto_compact_token_limit = 6144
      instructions = "Synthetic owned instructions B"
      developer_instructions = ""
      compact_prompt = "Synthetic owned compact B"
      model_reasoning_summary = "detailed"
      model_verbosity = "high"
      """)

    assert_projection(config, @profile_b)
  end

  test "empty nested tables receive parsed defaults while explicit settings remain distinct",
       ctx do
    defaults = read(ctx, "", "[analytics]\n[sandbox_workspace_write]\n")

    assert Map.fetch!(defaults, "analytics") === %{"enabled" => nil}

    assert Map.fetch!(defaults, "sandbox_workspace_write") === %{
             "writable_roots" => [],
             "network_access" => false,
             "exclude_tmpdir_env_var" => false,
             "exclude_slash_tmp" => false
           }

    owned_root = Path.join(ctx.root, "workspace")

    explicit =
      read(ctx, "", """
      [analytics]
      enabled = false
      [sandbox_workspace_write]
      writable_roots = [#{JSON.encode!(owned_root)}]
      network_access = true
      exclude_tmpdir_env_var = true
      exclude_slash_tmp = true
      """)

    assert Map.fetch!(explicit, "analytics") === %{"enabled" => false}

    assert Map.fetch!(explicit, "sandbox_workspace_write") === %{
             "writable_roots" => [owned_root],
             "network_access" => true,
             "exclude_tmpdir_env_var" => true,
             "exclude_slash_tmp" => true
           }
  end

  # Every case below reads metadata only in ManagedRequirementsFixture's private
  # namespaces. Only initialization, config/read and idle metadata requests are sent.
  test "absent selection options stay native nulls without copying runtime defaults", ctx do
    config = read(ctx, "", "", @selection_root_config)

    assert_projection(config, %{
      "approvals_reviewer" => nil,
      "forced_login_method" => nil,
      "forced_chatgpt_workspace_id" => nil,
      "model_auto_compact_token_limit_scope" => nil,
      "sandbox_mode" => nil,
      "web_search" => nil
    })
  end

  test "user API and single-workspace metadata preserves total workspace-write cached selections",
       ctx do
    config =
      read(
        ctx,
        """
        approvals_reviewer = "user"
        forced_login_method = "api"
        forced_chatgpt_workspace_id = "123e4567-e89b-42d3-a456-426614174000"
        model_auto_compact_token_limit_scope = "total"
        sandbox_mode = "workspace-write"
        web_search = "cached"
        """,
        "",
        @selection_root_config
      )

    assert_projection(config, %{
      "approvals_reviewer" => "user",
      "forced_login_method" => "api",
      "forced_chatgpt_workspace_id" => "123e4567-e89b-42d3-a456-426614174000",
      "model_auto_compact_token_limit_scope" => "total",
      "sandbox_mode" => "workspace-write",
      "web_search" => "cached"
    })
  end

  test "auto-review ChatGPT and workspace-list metadata preserves body-prefix full-access indexed selections",
       ctx do
    config =
      read(
        ctx,
        """
        approvals_reviewer = "auto_review"
        forced_login_method = "chatgpt"
        forced_chatgpt_workspace_id = ["123e4567-e89b-42d3-a456-426614174001", "123e4567-e89b-42d3-a456-426614174000"]
        model_auto_compact_token_limit_scope = "body_after_prefix"
        sandbox_mode = "danger-full-access"
        web_search = "indexed"
        """,
        "",
        @selection_root_config
      )

    assert_projection(config, %{
      "approvals_reviewer" => "auto_review",
      "forced_login_method" => "chatgpt",
      "forced_chatgpt_workspace_id" => [
        "123e4567-e89b-42d3-a456-426614174001",
        "123e4567-e89b-42d3-a456-426614174000"
      ],
      "model_auto_compact_token_limit_scope" => "body_after_prefix",
      "sandbox_mode" => "danger-full-access",
      "web_search" => "indexed"
    })
  end

  test "legacy reviewer alias normalizes while empty workspace and live-search metadata stay explicit",
       ctx do
    config =
      read(
        ctx,
        """
        approvals_reviewer = "guardian_subagent"
        forced_chatgpt_workspace_id = []
        sandbox_mode = "read-only"
        web_search = "live"
        """,
        "",
        @selection_root_config
      )

    # The alias is accepted input but serialized canonically as auto_review.
    # Empty list is distinct from absent/null; no workspace authorization is tested.
    assert_projection(config, %{
      "approvals_reviewer" => "auto_review",
      "forced_login_method" => nil,
      "forced_chatgpt_workspace_id" => [],
      "model_auto_compact_token_limit_scope" => nil,
      "sandbox_mode" => "read-only",
      "web_search" => "live"
    })
  end

  defp read(ctx, scalars \\ "", tables \\ "", root_config \\ @root_config) do
    input = root_config <> scalars <> @tables <> tables
    File.write!(ctx.config, input)
    pid = ManagedRequirementsFixture.start(ctx, "owned_config_option_projections")
    response = call(pid, "config/read", %{})
    assert File.read!(ctx.config) === input
    assert File.read!(ctx.requirements) === @requirements
    ManagedRequirementsFixture.assert_idle(pid)
    ManagedRequirementsFixture.close(ctx, pid)
    Map.fetch!(response, "config")
  end

  defp assert_projection(config, expected) do
    for {field, value} <- expected do
      assert Map.fetch!(config, field) === value
    end
  end
end
