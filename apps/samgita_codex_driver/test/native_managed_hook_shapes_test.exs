defmodule SamgitaCodexDriver.NativeManagedHookShapesTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ManagedRequirementsFixture, Session}
  import SamgitaCodexDriver.TurnFixture, only: [call: 3, upstream_error: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @events ~w(PreToolUse PermissionRequest PostToolUse PreCompact PostCompact SessionStart SessionEnd UserPromptSubmit SubagentStart SubagentStop Stop Interrupt)
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

    for dir <- ~w(home codex workspace tmp system managed-hook-source windows-hook-source),
        do: File.mkdir_p!(Path.join(root, dir))

    on_exit(fn -> File.rm_rf!(root) end)
    requirements = Path.join(root, "system/requirements.toml")
    config = Path.join(root, "codex/config.toml")

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
    name = "Nonexecuting complete managed hook metadata fixture"
    base_url = "http://127.0.0.1:9/v1"
    wire_api = "responses"
    requires_openai_auth = false
    supports_websockets = false
    request_max_retries = 0
    stream_max_retries = 0
    """

    File.write!(config, config_bytes)

    ctx = %{
      binary: Path.expand(binary),
      root: root,
      requirements: requirements,
      config: config,
      config_bytes: config_bytes,
      managed_dir: Path.join(root, "managed-hook-source"),
      windows_managed_dir: Path.join(root, "windows-hook-source")
    }

    source = @common <> hook_source(ctx)
    File.write!(requirements, source)
    assert_files(ctx, source)
    Map.put(ctx, :source, source)
  end

  test "complete hook metadata follows removal restoration and cold restart without running commands",
       ctx do
    expected = expected_hooks(ctx)
    pid = start(ctx)
    old_native_pid = proof(ctx)["native_pid"]
    assert_files(ctx, ctx.source)
    assert read(ctx, pid, ctx.source) === expected
    assert read(ctx, pid, ctx.source) === expected

    File.write!(ctx.requirements, @common)
    assert read(ctx, pid, @common) === nil
    File.write!(ctx.requirements, ctx.source)
    assert read(ctx, pid, ctx.source) === expected
    close(ctx, pid, ctx.source)

    cold = start(ctx)
    refute proof(ctx)["native_pid"] == old_native_pid
    assert_files(ctx, ctx.source)
    assert read(ctx, cold, ctx.source) === expected
    close(ctx, cold, ctx.source)
  end

  test "all retained handler variants are reported as inert managed metadata", ctx do
    source =
      ctx.source <>
        """
        [[hooks.PreToolUse.hooks]]
        type = "mcp_tool"
        server = "owned-inert-server"
        tool = "owned_inert_tool"
        input = { markers = ["owned-a", "owned-b"], amount = 7, nested = { enabled = false } }
        timeout = 13
        statusMessage = "Owned inert MCP metadata"
        [[hooks.PreToolUse.hooks]]
        type = "prompt"
        [[hooks.PreToolUse.hooks]]
        type = "agent"
        """

    expected =
      Map.update!(expected_hooks(ctx), "PreToolUse", fn [group] ->
        variants = [
          %{
            "type" => "mcp_tool",
            "server" => "owned-inert-server",
            "tool" => "owned_inert_tool",
            "input" => %{
              "markers" => ["owned-a", "owned-b"],
              "amount" => 7,
              "nested" => %{"enabled" => false}
            },
            "timeoutSec" => 13,
            "statusMessage" => "Owned inert MCP metadata"
          },
          %{"type" => "prompt"},
          %{"type" => "agent"}
        ]

        [Map.update!(group, "hooks", &(&1 ++ variants))]
      end)

    File.write!(ctx.requirements, source)
    pid = start(ctx)
    assert read(ctx, pid, source) === expected
    File.write!(ctx.requirements, ctx.source)
    assert read(ctx, pid, ctx.source) === expected_hooks(ctx)
    File.write!(ctx.requirements, source)
    assert read(ctx, pid, source) === expected
    native = proof(ctx)["native_pid"]
    close(ctx, pid, source)
    cold = start(ctx)
    refute proof(ctx)["native_pid"] == native
    assert read(ctx, cold, source) === expected
    close(ctx, cold, source)
  end

  test "typed malformed path and hook reads preserve files and recover the complete metadata",
       ctx do
    expected = expected_hooks(ctx)
    pid = start(ctx)
    assert read(ctx, pid, ctx.source) === expected

    interrupt_command =
      "printf owned-Interrupt > '#{Path.join(ctx.root, "forbidden-Interrupt")}'"

    replacements = [
      {"managed_dir = #{JSON.encode!(ctx.managed_dir)}", "managed_dir = 17"},
      {"windows_managed_dir = #{JSON.encode!(ctx.windows_managed_dir)}",
       "windows_managed_dir = 17"},
      {"command = #{JSON.encode!(interrupt_command)}", "command = 17"}
    ]

    for {valid, invalid} <- replacements do
      assert length(:binary.matches(ctx.source, valid)) == 1
      malformed = String.replace(ctx.source, valid, invalid, global: false)
      refute malformed == ctx.source

      try do
        File.write!(ctx.requirements, malformed)
        assert_files(ctx, malformed)
        error = upstream_error(pid, "configRequirements/read", nil)
        assert error["code"] == -32_603
        assert error["message"] =~ "failed to read configuration layers:"
        assert error["message"] =~ "failed to parse requirements layer"
        assert error["message"] =~ "/etc/codex/requirements.toml"
        assert_idle(ctx, pid, malformed)
      after
        File.write!(ctx.requirements, ctx.source)
        assert_files(ctx, ctx.source)
      end

      assert read(ctx, pid, ctx.source) === expected
    end

    close(ctx, pid, ctx.source)
  end

  defp hook_source(ctx) do
    paths = """
    [hooks]
    managed_dir = #{JSON.encode!(ctx.managed_dir)}
    windows_managed_dir = #{JSON.encode!(ctx.windows_managed_dir)}
    """

    paths <>
      Enum.map_join(Enum.with_index(@events, 1), "\n", fn {event, index} ->
        command = "printf owned-#{event} > '#{Path.join(ctx.root, "forbidden-#{event}")}'"

        """
        [[hooks.#{event}]]
        matcher = "owned-#{event}"
        [[hooks.#{event}.hooks]]
        type = "command"
        command = #{JSON.encode!(command)}
        commandWindows = "echo metadata-only-#{event}"
        timeout = #{index}
        async = false
        statusMessage = "shape #{event}"
        additionalContextLimit = #{index}
        """
      end)
  end

  # These fourteen response members are prescribed independently of the response
  # and schema. Each event's positive row is explicit; input timeout maps to timeoutSec.
  defp expected_hooks(ctx) do
    %{
      "managedDir" => ctx.managed_dir,
      "windowsManagedDir" => ctx.windows_managed_dir,
      "PreToolUse" => expected_group(ctx, "PreToolUse", 1),
      "PermissionRequest" => expected_group(ctx, "PermissionRequest", 2),
      "PostToolUse" => expected_group(ctx, "PostToolUse", 3),
      "PreCompact" => expected_group(ctx, "PreCompact", 4),
      "PostCompact" => expected_group(ctx, "PostCompact", 5),
      "SessionStart" => expected_group(ctx, "SessionStart", 6),
      "SessionEnd" => expected_group(ctx, "SessionEnd", 7),
      "UserPromptSubmit" => expected_group(ctx, "UserPromptSubmit", 8),
      "SubagentStart" => expected_group(ctx, "SubagentStart", 9),
      "SubagentStop" => expected_group(ctx, "SubagentStop", 10),
      "Stop" => expected_group(ctx, "Stop", 11),
      "Interrupt" => expected_group(ctx, "Interrupt", 12)
    }
  end

  defp expected_group(ctx, event, number) do
    [
      %{
        "matcher" => "owned-#{event}",
        "hooks" => [
          %{
            "type" => "command",
            "command" => "printf owned-#{event} > '#{Path.join(ctx.root, "forbidden-#{event}")}'",
            "commandWindows" => "echo metadata-only-#{event}",
            "timeoutSec" => number,
            "async" => false,
            "statusMessage" => "shape #{event}",
            "additionalContextLimit" => number
          }
        ]
      }
    ]
  end

  defp read(ctx, pid, source) do
    assert_files(ctx, source)
    response = call(pid, "configRequirements/read", nil)
    assert Map.fetch!(response, "supportsIndependentSpeedModes") === true
    hooks = response |> Map.fetch!("requirements") |> Map.fetch!("hooks")
    assert_idle(ctx, pid, source)
    hooks
  end

  defp assert_idle(ctx, pid, source) do
    assert_files(ctx, source)
    ManagedRequirementsFixture.assert_idle(pid)
    assert Session.uncertain_operations(pid) === []
    assert_files(ctx, source)
  end

  defp assert_files(ctx, source) do
    assert File.read!(ctx.requirements) === source
    assert File.read!(ctx.config) === ctx.config_bytes
    refute File.exists?(Path.join(ctx.root, "codex/auth.json"))

    for dir <- [ctx.managed_dir, ctx.windows_managed_dir] do
      assert File.lstat!(dir).type == :directory
      assert File.ls!(dir) === []
    end

    for event <- @events,
        do: refute(File.exists?(Path.join(ctx.root, "forbidden-#{event}")))
  end

  defp close(ctx, pid, source) do
    assert_idle(ctx, pid, source)
    ManagedRequirementsFixture.close(ctx, pid)
    assert_files(ctx, source)
  end

  defp start(ctx), do: ManagedRequirementsFixture.start(ctx, "owned_complete_hook_metadata")

  defp proof(ctx), do: ctx.root |> Path.join("proof.json") |> File.read!() |> JSON.decode!()
end
