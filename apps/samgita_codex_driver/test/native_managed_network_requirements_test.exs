defmodule SamgitaCodexDriver.NativeManagedNetworkRequirementsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ManagedRequirementsFixture, Session, TurnFixture}
  import ManagedRequirementsFixture, only: [close: 2, assert_idle: 1]
  import TurnFixture, only: [call: 3, upstream_error: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @common """
  allow_browser_and_computer_use = false
  allow_appshots = false
  allow_remote_control = false
  """
  @network_fields ~w(enabled httpPort socksPort allowUpstreamProxy dangerouslyAllowNonLoopbackProxy dangerouslyAllowAllUnixSockets domains managedAllowedDomainsOnly allowedDomains deniedDomains unixSockets allowUnixSockets allowLocalBinding)

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
    network_proxy = false
    apps = false
    plugins = false
    recommended_plugins = false
    shell_snapshot = false
    [model_providers.fixture]
    name = "Nonexecuting disabled-network metadata fixture"
    base_url = "http://127.0.0.1:9/v1"
    wire_api = "responses"
    requires_openai_auth = false
    supports_websockets = false
    request_max_retries = 0
    stream_max_retries = 0
    """)

    ctx = %{
      binary: Path.expand(binary),
      root: root,
      config: config,
      requirements: Path.join(root, "system/requirements.toml"),
      allow_socket: Path.join(root, "never-opened-allow.sock"),
      deny_socket: Path.join(root, "never-opened-deny.sock")
    }

    File.write!(ctx.requirements, canonical(ctx))
    before = File.read!(config)
    on_exit(fn -> assert File.read!(config) === before end)
    ctx
  end

  test "disabled managed network exposes exact canonical maps and sorted compatibility lists",
       ctx do
    before = File.read!(ctx.config)
    pid = start(ctx)
    response = call(pid, "configRequirements/read", nil)
    assert response["supportsIndependentSpeedModes"] === true
    assert Map.fetch!(response["requirements"], "network") === expected(ctx)
    assert File.read!(ctx.requirements) === canonical(ctx)
    assert File.read!(ctx.config) === before
    assert_inert(ctx, pid)
    close(ctx, pid)
  end

  test "absent sparse and empty maps preserve exact native null versus object presence", ctx do
    File.write!(ctx.requirements, @common)
    pid = start(ctx)
    baseline = call(pid, "configRequirements/read", nil)
    assert Map.fetch!(baseline["requirements"], "network") === nil
    sparse = Map.new(@network_fields, &{&1, nil}) |> Map.put("enabled", false)

    for {source, network} <- [
          {@common <> "[experimental_network]\nenabled = false\n", sparse},
          {@common <>
             "[experimental_network]\nenabled = false\n" <>
             "[experimental_network.domains]\n[experimental_network.unix_sockets]\n",
           sparse |> Map.put("domains", %{}) |> Map.put("unixSockets", %{})},
          {@common <>
             "[experimental_network]\nenabled = false\n" <>
             "allowed_domains = []\ndenied_domains = []\nallow_unix_sockets = []\n", sparse}
        ] do
      File.write!(ctx.requirements, source)
      response = call(pid, "configRequirements/read", nil)
      assert response === put_in(baseline, ["requirements", "network"], network)
      assert File.read!(ctx.requirements) === source
      assert_inert(ctx, pid)
    end

    File.write!(ctx.requirements, @common)
    assert call(pid, "configRequirements/read", nil) === baseline
    assert_inert(ctx, pid)
    close(ctx, pid)
  end

  test "legacy duplicates normalize deterministically with deny taking precedence", ctx do
    source =
      scalars() <>
        ~s(allowed_domains = ["z.owned.invalid", "shared.invalid", "a.owned.invalid", "z.owned.invalid"]) <>
        "\n" <>
        ~s(denied_domains = ["shared.invalid", "blocked.owned.invalid", "shared.invalid"]) <>
        "\n" <>
        "allow_unix_sockets = [#{JSON.encode!(ctx.allow_socket)}, #{JSON.encode!(ctx.allow_socket)}]\n"

    File.write!(ctx.requirements, source)
    pid = start(ctx)
    response = call(pid, "configRequirements/read", nil)
    normalized = Map.put(expected(ctx), "unixSockets", %{ctx.allow_socket => "allow"})
    assert response["requirements"]["network"] === normalized
    assert File.read!(ctx.requirements) === source
    assert_inert(ctx, pid)
    close(ctx, pid)
  end

  test "owned-file reload and cold restart retain metadata without a user-config write", ctx do
    before = File.read!(ctx.config)
    pid = start(ctx)
    baseline = call(pid, "configRequirements/read", nil)
    source = canonical(ctx, true)
    File.write!(ctx.requirements, source)
    refreshed = call(pid, "configRequirements/read", nil)

    expected_response =
      baseline
      |> put_in(["requirements", "network", "httpPort"], 43_129)
      |> put_in(["requirements", "network", "domains", "new.owned.invalid"], "deny")
      |> put_in(["requirements", "network", "deniedDomains"], [
        "blocked.owned.invalid",
        "new.owned.invalid",
        "shared.invalid"
      ])

    assert refreshed === expected_response
    assert File.read!(ctx.config) === before
    assert File.read!(ctx.requirements) === source
    assert_inert(ctx, pid)
    close(ctx, pid)

    cold = start(ctx)
    assert call(cold, "configRequirements/read", nil) === refreshed
    assert File.read!(ctx.config) === before
    assert File.read!(ctx.requirements) === source
    assert_inert(ctx, cold)

    File.write!(ctx.requirements, canonical(ctx))
    assert call(cold, "configRequirements/read", nil) === baseline
    assert File.read!(ctx.config) === before
    assert_inert(ctx, cold)
    close(ctx, cold)
  end

  test "invalid managed network values and mixed representations fail reads and recover", ctx do
    pid = start(ctx)
    baseline = call(pid, "configRequirements/read", nil)
    before = File.read!(ctx.config)
    source = canonical(ctx)

    boolean_errors =
      for field <-
            ~w(enabled allow_upstream_proxy dangerously_allow_non_loopback_proxy dangerously_allow_all_unix_sockets managed_allowed_domains_only allow_local_binding) do
        value = if field == "managed_allowed_domains_only", do: "true", else: "false"
        {String.replace(source, "#{field} = #{value}\n", "#{field} = 17\n"), "expected a boolean"}
      end

    port_errors =
      for {field, value} <- [{"http_port", "43128"}, {"socks_port", "41080"}],
          invalid <- ["-1", "65536", "\"43128\""] do
        {String.replace(source, "#{field} = #{value}\n", "#{field} = #{invalid}\n"), "u16"}
      end

    errors =
      boolean_errors ++
        port_errors ++
        [
          {String.replace(
             source,
             "\"a.owned.invalid\" = \"allow\"",
             "\"a.owned.invalid\" = \"prompt\""
           ), "unknown variant `prompt`"},
          {String.replace(
             source,
             "#{JSON.encode!(ctx.allow_socket)} = \"allow\"",
             "#{JSON.encode!(ctx.allow_socket)} = \"prompt\""
           ), "unknown variant `prompt`"},
          {String.replace(
             source,
             "[experimental_network]\n",
             "[experimental_network]\nallowed_domains = []\n"
           ),
           "`experimental_network.domains` cannot be combined with legacy `allowed_domains` or `denied_domains`"},
          {String.replace(
             source,
             "[experimental_network]\n",
             "[experimental_network]\nallow_unix_sockets = []\n"
           ),
           "`experimental_network.unix_sockets` cannot be combined with legacy `allow_unix_sockets`"}
        ]

    for {invalid, diagnostic} <- errors do
      refute invalid == source

      try do
        File.write!(ctx.requirements, invalid)
        error = upstream_error(pid, "configRequirements/read", nil)
        assert error["code"] == -32_603
        assert error["message"] =~ "failed to read configuration layers:"
        assert error["message"] =~ "failed to parse requirements layer"
        assert error["message"] =~ "/etc/codex/requirements.toml"
        assert error["message"] =~ diagnostic
        assert File.read!(ctx.config) === before
        assert_inert(ctx, pid)
      after
        File.write!(ctx.requirements, source)
      end

      assert call(pid, "configRequirements/read", nil) === baseline
      assert File.read!(ctx.config) === before
      assert_inert(ctx, pid)
    end

    close(ctx, pid)
  end

  defp scalars do
    @common <>
      """
      [experimental_network]
      enabled = false
      http_port = 43128
      socks_port = 41080
      allow_upstream_proxy = false
      dangerously_allow_non_loopback_proxy = false
      dangerously_allow_all_unix_sockets = false
      managed_allowed_domains_only = true
      allow_local_binding = false
      """
  end

  defp canonical(ctx, refreshed \\ false) do
    source =
      scalars() <>
        """
        [experimental_network.domains]
        "z.owned.invalid" = "allow"
        "a.owned.invalid" = "allow"
        "shared.invalid" = "deny"
        "blocked.owned.invalid" = "deny"
        """ <>
        if(refreshed, do: "\"new.owned.invalid\" = \"deny\"\n", else: "") <>
        "[experimental_network.unix_sockets]\n" <>
        "#{JSON.encode!(ctx.deny_socket)} = \"deny\"\n" <>
        "#{JSON.encode!(ctx.allow_socket)} = \"allow\"\n"

    if refreshed,
      do: String.replace(source, "http_port = 43128", "http_port = 43129"),
      else: source
  end

  defp expected(ctx) do
    %{
      "enabled" => false,
      "httpPort" => 43_128,
      "socksPort" => 41_080,
      "allowUpstreamProxy" => false,
      "dangerouslyAllowNonLoopbackProxy" => false,
      "dangerouslyAllowAllUnixSockets" => false,
      "managedAllowedDomainsOnly" => true,
      "allowLocalBinding" => false,
      "domains" => %{
        "a.owned.invalid" => "allow",
        "z.owned.invalid" => "allow",
        "blocked.owned.invalid" => "deny",
        "shared.invalid" => "deny"
      },
      "allowedDomains" => ["a.owned.invalid", "z.owned.invalid"],
      "deniedDomains" => ["blocked.owned.invalid", "shared.invalid"],
      "unixSockets" => %{ctx.allow_socket => "allow", ctx.deny_socket => "deny"},
      "allowUnixSockets" => [ctx.allow_socket]
    }
  end

  defp assert_inert(ctx, pid) do
    assert_idle(pid)
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
    refute File.exists?(ctx.allow_socket)
    refute File.exists?(ctx.deny_socket)

    # Inspect only the fixture's proved private native network namespace.
    proof = ctx.root |> Path.join("proof.json") |> File.read!() |> JSON.decode!()
    native = proof["native_pid"]
    network = File.read_link!("/proc/#{native}/ns/net")
    assert network == proof["namespaces"]["net"]
    refute network == proof["parents"]["net"]

    for table <- ~w(tcp tcp6) do
      rows = File.read!("/proc/#{native}/net/#{table}") |> String.split("\n", trim: true)
      assert Enum.drop(rows, 1) == [], "Disabled metadata opened an owned #{table} socket"
    end
  end

  defp start(ctx),
    do: ManagedRequirementsFixture.start(ctx, "owned_managed_network_requirements")
end
