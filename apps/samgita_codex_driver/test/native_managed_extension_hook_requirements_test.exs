defmodule SamgitaCodexDriver.NativeManagedExtensionHookRequirementsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ManagedRequirementsFixture, Session}
  import SamgitaCodexDriver.TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @common """
  allow_browser_and_computer_use = false
  allow_appshots = false
  allow_remote_control = false
  allow_managed_hooks_only = true
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
    config = Path.join(root, "codex/config.toml")
    File.write!(requirements, @common)

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
    name = "Nonexecuting extension and hook requirements fixture"
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

  test "extension headers retain order and templates through explicit clearing removal and owned restart",
       ctx do
    pid = start(ctx)
    anchor = "[browser_use]\nallow_webmcp = false\n"

    selected =
      anchor <>
        """
        [browser_use.extension]
        request_headers = [{ name = "x-owned", value = "ChatGPT/{{session_id}}" }, { name = "x-owned", value = "fixed λ🙂" }]
        """

    expected = %{
      "requestHeaders" => [
        %{"name" => "x-owned", "value" => "ChatGPT/{{session_id}}"},
        %{"name" => "x-owned", "value" => "fixed λ🙂"}
      ]
    }

    first = read(ctx, pid, selected)
    assert Map.fetch!(first["browserUse"], "extension") === expected
    cleared = read(ctx, pid, anchor <> "[browser_use.extension]\nrequest_headers = []\n")
    assert Map.fetch!(cleared["browserUse"], "extension") === %{"requestHeaders" => []}
    removed = read(ctx, pid, anchor)
    assert Map.fetch!(removed["browserUse"], "extension") === nil
    assert Map.fetch!(removed["browserUse"], "allowWebmcp") === false
    assert read(ctx, pid, selected)["browserUse"]["extension"] === expected
    cold = restart(ctx, pid)
    assert read(ctx, cold, selected)["browserUse"]["extension"] === expected
    ManagedRequirementsFixture.close(ctx, cold)
  end

  test "command hook metadata moves between events and changes selected fields without running a hook",
       ctx do
    pid = start(ctx)
    command_a = "printf forbidden-a > " <> Path.join(ctx.root, "forbidden-hook-a")
    command_b = "printf forbidden-b > " <> Path.join(ctx.root, "forbidden-hook-b")

    initial = """
    [[hooks.PreToolUse]]
    matcher = "apply_patch"
    [[hooks.PreToolUse.hooks]]
    type = "command"
    command = #{JSON.encode!(command_a)}
    commandWindows = "echo metadata-only-a"
    timeout = 7
    async = true
    statusMessage = ""
    additionalContextLimit = 0
    """

    expected_a = [
      %{
        "matcher" => "apply_patch",
        "hooks" => [
          %{
            "type" => "command",
            "command" => command_a,
            "commandWindows" => "echo metadata-only-a",
            "timeoutSec" => 7,
            "async" => true,
            "statusMessage" => "",
            "additionalContextLimit" => 0
          }
        ]
      }
    ]

    first = read(ctx, pid, initial)
    assert Map.fetch!(first["hooks"], "PreToolUse") === expected_a
    assert Map.fetch!(first["hooks"], "PostToolUse") === []

    moved = """
    [[hooks.PostToolUse]]
    matcher = "exec_command"
    [[hooks.PostToolUse.hooks]]
    type = "command"
    command = #{JSON.encode!(command_b)}
    commandWindows = ""
    timeout = 11
    async = false
    statusMessage = "Synthetic idle metadata λ"
    additionalContextLimit = 17
    """

    expected_b = [
      %{
        "matcher" => "exec_command",
        "hooks" => [
          %{
            "type" => "command",
            "command" => command_b,
            "commandWindows" => "",
            "timeoutSec" => 11,
            "async" => false,
            "statusMessage" => "Synthetic idle metadata λ",
            "additionalContextLimit" => 17
          }
        ]
      }
    ]

    changed = read(ctx, pid, moved)
    assert Map.fetch!(changed["hooks"], "PreToolUse") === []
    assert Map.fetch!(changed["hooks"], "PostToolUse") === expected_b
    cold = restart(ctx, pid)
    persisted = read(ctx, cold, moved)
    assert Map.fetch!(persisted["hooks"], "PreToolUse") === []
    assert Map.fetch!(persisted["hooks"], "PostToolUse") === expected_b
    assert Map.fetch!(read(ctx, cold, ""), "hooks") === nil
    ManagedRequirementsFixture.close(ctx, cold)
  end

  test "mixed inert MCP prompt and agent hook metadata keeps exact order across reload removal and restart",
       ctx do
    pid = start(ctx)
    group = "[[hooks.PermissionRequest]]\nmatcher = 'owned-metadata-only'\n"

    mcp = """
    [[hooks.PermissionRequest.hooks]]
    type = "mcp_tool"
    server = "owned-unused-server"
    tool = "owned-unused-tool"
    input = { text = "synthetic λ", count = 2, enabled = false, nested = { fixed = "value" } }
    timeout = 9
    statusMessage = "inert"
    """

    prompt = "[[hooks.PermissionRequest.hooks]]\ntype = 'prompt'\n"
    agent = "[[hooks.PermissionRequest.hooks]]\ntype = 'agent'\n"

    expected_mcp = %{
      "type" => "mcp_tool",
      "server" => "owned-unused-server",
      "tool" => "owned-unused-tool",
      "input" => %{
        "text" => "synthetic λ",
        "count" => 2,
        "enabled" => false,
        "nested" => %{"fixed" => "value"}
      },
      "timeoutSec" => 9,
      "statusMessage" => "inert"
    }

    initial = group <> mcp <> prompt <> agent

    expected = [
      %{
        "matcher" => "owned-metadata-only",
        "hooks" => [expected_mcp, %{"type" => "prompt"}, %{"type" => "agent"}]
      }
    ]

    assert Map.fetch!(read(ctx, pid, initial)["hooks"], "PermissionRequest") === expected
    reversed = group <> agent <> prompt <> mcp

    reordered = [
      %{
        "matcher" => "owned-metadata-only",
        "hooks" => [%{"type" => "agent"}, %{"type" => "prompt"}, expected_mcp]
      }
    ]

    assert Map.fetch!(read(ctx, pid, reversed)["hooks"], "PermissionRequest") === reordered
    assert Map.fetch!(read(ctx, pid, ""), "hooks") === nil
    assert Map.fetch!(read(ctx, pid, initial)["hooks"], "PermissionRequest") === expected
    cold = restart(ctx, pid)
    assert Map.fetch!(read(ctx, cold, initial)["hooks"], "PermissionRequest") === expected
    ManagedRequirementsFixture.close(ctx, cold)
  end

  defp read(ctx, pid, selected) do
    source = @common <> selected
    File.write!(ctx.requirements, source)
    response = call(pid, "configRequirements/read", nil)
    assert Map.fetch!(response, "supportsIndependentSpeedModes") === true
    assert File.read!(ctx.requirements) === source
    assert File.read!(ctx.config) === ctx.config_bytes
    ManagedRequirementsFixture.assert_idle(pid)
    assert Session.uncertain_operations(pid) === []

    for name <- ~w(forbidden-hook-a forbidden-hook-b),
        do: refute(File.exists?(Path.join(ctx.root, name)))

    Map.fetch!(response, "requirements")
  end

  defp start(ctx), do: ManagedRequirementsFixture.start(ctx, "owned_extension_hook_requirements")

  defp restart(ctx, pid) do
    old = proof(ctx)["native_pid"]
    ManagedRequirementsFixture.close(ctx, pid)
    next = start(ctx)
    refute proof(ctx)["native_pid"] == old
    next
  end

  defp proof(ctx), do: ctx.root |> Path.join("proof.json") |> File.read!() |> JSON.decode!()
end
