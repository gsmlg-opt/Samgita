defmodule SamgitaCodexDriver.NativeInitializationMetadataTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

  setup tags do
    ctx = TurnFixture.setup(tags)

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    TurnFixture.configure_model(ctx, %{})
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      "cli_auth_credentials_store = \"ephemeral\"\n" <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    config_bytes = File.read!(config)
    on_exit(fn -> assert File.read!(config) == config_bytes end)
    ctx
  end

  test "explicit null capabilities initialize a real native connection and fresh clients select their agent suffix",
       ctx do
    first = start(ctx)
    name = "samgita_owned_initialize_a"
    params = %{"clientInfo" => %{"name" => name, "version" => "1.2.3"}, "capabilities" => nil}

    assert {:ok, %{"id" => "owned-null-initialize", "result" => response}} =
             Session.request_native(first, %{
               "id" => "owned-null-initialize",
               "method" => "initialize",
               "params" => params
             })

    assert_metadata(ctx, first, response, name, "1.2.3")
    assert :ok = Session.close(first)

    second = start(ctx)
    other = "samgita_owned_initialize_b"

    assert {:ok, %{"result" => changed}} =
             Session.initialize(second, %{"name" => other, "version" => "4.5.6\r\nλ"}, %{})

    assert_metadata(ctx, second, changed, other, "4.5.6___")
    refute changed["userAgent"] == response["userAgent"]
    refute String.contains?(changed["userAgent"], ["\r", "\n", "λ"])
    assert :ok = Session.close(second)
  end

  test "invalid client header identity leaves native initialization uncommitted for a valid retry",
       ctx do
    pid = start(ctx)
    invalid = "samgita_owned_bad\nidentity"

    assert {:error, %Error{code: :upstream_error, uncertain: false, wire: %{"error" => error}}} =
             Session.initialize(pid, %{"name" => invalid, "version" => "1.0.0"}, %{})

    assert error == %{
             "code" => -32_600,
             "message" =>
               "Invalid clientInfo.name: '#{invalid}'. Must be a valid HTTP header value."
           }

    assert %{phase: :new, pending: 0, uncertain: 0} = Session.status(pid)
    assert ModelFixture.requests(ctx.fixture) == []
    name = "samgita_owned_valid_retry"

    assert {:ok, %{"result" => response}} =
             Session.initialize(pid, %{"name" => name, "version" => "2.0.0"}, %{})

    assert_metadata(ctx, pid, response, name, "2.0.0")
    refute String.contains?(response["userAgent"], "samgita_owned_bad")
    assert :ok = Session.close(pid)
  end

  defp assert_metadata(ctx, pid, response, name, version) do
    assert Enum.sort(Map.keys(response)) == ~w(codexHome platformFamily platformOs userAgent)
    assert Map.fetch!(response, "codexHome") == ctx.fixture.codex_home
    assert Map.fetch!(response, "platformFamily") == "unix"
    assert Map.fetch!(response, "platformOs") == "linux"
    agent = Map.fetch!(response, "userAgent")
    assert String.starts_with?(agent, name <> "/0.163.0 (")
    assert String.ends_with?(agent, " (#{name}; #{version})")
    assert call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert ModelFixture.requests(ctx.fixture) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request))
    refute Enum.any?(events, &(&1.wire["method"] in ["turn/started", "turn/completed"]))
  end

  defp start(ctx) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: ctx.binary,
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
             cwd: ctx.fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => ctx.fixture.home,
               "CODEX_HOME" => ctx.fixture.codex_home,
               "TMPDIR" => ctx.root,
               "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)
    pid
  end
end
