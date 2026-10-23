defmodule SamgitaCodexDriver.NativeBedrockProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag :isolated_bedrock
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_bedrock_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @discover "account/bedrock/discover"
  @setup "account/bedrock/setup"
  @gov "account/bedrock/checkGovCloudRequirements"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-bedrock-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    File.mkdir!(root)

    for directory <- ~w(home codex workspace tmp), do: File.mkdir_p!(Path.join(root, directory))

    ctx = %{
      binary: Path.expand(binary),
      root: root,
      env_mode: tags[:env_mode] || "both",
      forced_chatgpt: tags[:forced_chatgpt] || false
    }

    on_exit(fn ->
      if File.exists?(Path.join(root, "journal.json")) do
        for started <- events(ctx, "native_started"),
            key <- ~w(pid controller_pid namespace_owner_pid),
            do: wait(fn -> not File.exists?("/proc/#{started[key]}") end)

        assert length(events(ctx, "native_closed")) == length(events(ctx, "native_started"))
      end

      File.rm_rf!(root)
    end)

    ctx
  end

  test "all three methods require experimental negotiation in driver and native", ctx do
    pid = start(ctx, false)
    before = config_bytes(ctx)

    for {method, params} <- [
          {@discover, %{}},
          {@setup, %{"type" => "environment", "region" => "us-east-1"}},
          {@gov, %{}}
        ] do
      count = length(events(ctx, "native_input"))

      assert {:error, %Error{code: :experimental_api_required, uncertain: false}} =
               Session.request(pid, method, params)

      assert length(events(ctx, "native_input")) == count
      id = "owned-bedrock-gate-#{System.unique_integer([:positive])}"

      assert {:error,
              %Error{
                code: :upstream_error,
                wire: %{"id" => ^id, "error" => %{"code" => -32_600, "message" => message}}
              }} = Session.request(pid, method, params, id: id, validation: :wire)

      assert message =~ "experimentalApi"
      assert length(events(ctx, "native_input")) == count + 1
      assert config_bytes(ctx) == before
    end

    assert_no_auth_files(ctx)
    finish(ctx, pid)
  end

  for {mode, region, types} <- [
        {"both", "us-west-2", ["accessKeys", "bedrockApiKey"]},
        {"default-only", nil, ["accessKeys", "bedrockApiKey"]},
        {"incomplete", nil, []}
      ] do
    @tag env_mode: mode
    test "#{mode} discovery returns local profile and environment metadata only", ctx do
      pid = start(ctx)
      before = config_bytes(ctx)

      assert call(pid, @discover, %{}) == %{
               "profiles" => [
                 %{"name" => "engineering", "region" => "us-west-2"},
                 %{"name" => "finance", "region" => nil}
               ],
               "environmentCredentials" =>
                 Enum.map(unquote(types), &%{"type" => &1, "region" => unquote(region)})
             }

      assert config_bytes(ctx) == before
      assert_no_auth_files(ctx)
      finish(ctx, pid)
    end
  end

  for mode <- ~w(access api) do
    @tag env_mode: mode
    test "#{mode} environment setup trims region and persists selection without AWS validation",
         ctx do
      pid = start(ctx)
      assert call(pid, @setup, %{"type" => "environment", "region" => " us-east-2 "}) == %{}
      assert_selection(ctx, pid, "us-east-2", nil)
      assert_no_auth_files(ctx)
      finish(ctx, pid)
    end
  end

  test "static profile selection and environment clearing survive cold native restart", ctx do
    pid = start(ctx)

    assert call(pid, @setup, %{
             "type" => "profile",
             "profile" => " engineering ",
             "region" => "us-west-2"
           }) == %{}

    assert_selection(ctx, pid, "us-west-2", "engineering")
    assert call(pid, @setup, %{"type" => "environment", "region" => "us-east-1"}) == %{}
    assert_selection(ctx, pid, "us-east-1", nil)
    assert_no_auth_files(ctx)
    persisted = config_bytes(ctx)
    finish(ctx, pid)

    restarted = start(ctx)
    assert_selection(ctx, restarted, "us-east-1", nil)
    assert config_bytes(ctx) == persisted
    assert length(events(ctx, "native_started")) == 2
    assert_no_auth_files(ctx)
    finish(ctx, restarted)
  end

  @tag env_mode: "none"
  test "unsupported region blank profile missing profile and missing environment preserve disk",
       ctx do
    pid = start(ctx)
    before = config_bytes(ctx)

    for {params, message, match} <- [
          {%{"type" => "profile", "profile" => "engineering", "region" => "us-west-1"},
           "Amazon Bedrock does not support region `us-west-1`", :exact},
          {%{"type" => "profile", "profile" => " ", "region" => "us-west-2"},
           "AWS profile name must not be empty.", :exact},
          {%{"type" => "profile", "profile" => "missing", "region" => "us-west-2"},
           "failed to load credentials for AWS profile `missing`:", :prefix},
          {%{"type" => "environment", "region" => "us-west-2"},
           "No AWS credentials found. Please Configure AWS credentials or complete AWS sign-in, then try again.",
           :exact}
        ] do
      failure = error(pid, @setup, params)
      assert failure["code"] == -32_600

      if match == :exact,
        do: assert(failure["message"] == message),
        else: assert(String.starts_with?(failure["message"], message))

      assert config_bytes(ctx) == before
      assert_no_auth_files(ctx)
    end

    finish(ctx, pid)
  end

  @tag forced_chatgpt: true
  test "forced ChatGPT login policy rejects discover and setup without modifying config", ctx do
    pid = start(ctx)
    before = config_bytes(ctx)

    for {method, params} <- [
          {@discover, %{}},
          {@setup, %{"type" => "environment", "region" => "us-east-1"}}
        ] do
      assert error(pid, method, params) == %{
               "code" => -32_600,
               "message" => "Amazon Bedrock login is disabled. Use ChatGPT login instead."
             }

      assert config_bytes(ctx) == before
      assert_no_auth_files(ctx)
    end

    finish(ctx, pid)
  end

  test "advisory GovCloud checks read latest configuration and require exact official hostnames",
       ctx do
    pid = start(ctx)
    assert call(pid, @gov, %{}) == %{"isGovCloud" => false, "shouldWarn" => false}
    write(pid, "model_providers.amazon-bedrock.aws.region", "us-west-2")

    write(
      pid,
      "model_providers.amazon-bedrock.base_url",
      "https://bedrock-mantle.us-gov-west-1.api.aws/openai/v1"
    )

    write(pid, "model_provider", "amazon-bedrock")

    assert call(pid, @gov, %{}) == %{"isGovCloud" => true, "shouldWarn" => true}

    write(
      pid,
      "model_providers.amazon-bedrock.base_url",
      "https://bedrock-mantle.us-west-2.api.aws/openai/v1"
    )

    assert call(pid, @gov, %{}) == %{"isGovCloud" => false, "shouldWarn" => false}

    write(
      pid,
      "model_providers.amazon-bedrock.base_url",
      "https://bedrock-mantle.us-gov-west-1.api.aws.synthetic.invalid/openai/v1"
    )

    assert call(pid, @gov, %{}) == %{"isGovCloud" => false, "shouldWarn" => false}
    assert_no_auth_files(ctx)
    finish(ctx, pid)
  end

  defp start(ctx, experimental \\ true) do
    args = [@script, "--codex", ctx.binary, "--root", ctx.root, "--env-mode", ctx.env_mode]
    args = if ctx.forced_chatgpt, do: args ++ ["--forced-chatgpt"], else: args

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: System.find_executable("python3"),
             args: args,
             cwd: Path.join(ctx.root, "workspace"),
             inherit_env: [],
             env: %{
               "HOME" => Path.join(ctx.root, "home"),
               "CODEX_HOME" => Path.join(ctx.root, "codex"),
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
               "PYTHONDONTWRITEBYTECODE" => "1"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(pid, %{"name" => "samgita_bedrock", "version" => "1"}, %{
               "experimentalApi" => experimental
             })

    wait(fn -> Enum.any?(events(ctx, "native_input"), &(&1["method"] == "initialized")) end)
    pid
  end

  defp assert_selection(ctx, pid, region, profile) do
    response = call(pid, "config/read", %{"includeLayers" => true})
    assert response["config"]["model_provider"] == "amazon-bedrock"
    layer = Enum.find(response["layers"], &(&1["name"]["type"] == "user"))
    assert layer["name"]["file"] == Path.join(ctx.root, "codex/config.toml")
    provider = layer["config"]["model_providers"]["amazon-bedrock"]
    expected = %{"region" => region}
    expected = if profile, do: Map.put(expected, "profile", profile), else: expected
    assert provider["aws"] == expected
    assert provider["http_headers"] == %{"X-Existing" => "preserved-synthetic"}
    assert config_bytes(ctx) =~ ~s(model_provider = "amazon-bedrock")
    assert config_bytes(ctx) =~ ~s(region = "#{region}")

    if profile,
      do: assert(config_bytes(ctx) =~ ~s(profile = "#{profile}")),
      else: refute(config_bytes(ctx) =~ "profile =")
  end

  defp write(pid, key, value) do
    result =
      call(pid, "config/value/write", %{
        "keyPath" => key,
        "value" => value,
        "mergeStrategy" => "replace"
      })

    assert result["status"] == "ok"
  end

  defp assert_no_auth_files(ctx) do
    for filename <- ~w(auth.json .env),
        do: refute(File.exists?(Path.join(ctx.root, "codex/#{filename}")))
  end

  defp finish(ctx, pid) do
    assert call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert Session.status(pid).phase == :ready
    assert Session.status(pid).interactions == 0
    assert Session.uncertain_operations(pid) == []
    assert {:ok, received} = Session.drain(pid)

    assert Enum.all?(
             received,
             &(&1.kind != :server_request and &1.wire["method"] != "turn/started")
           )

    proof = journal(ctx)["namespace"]
    assert proof["parent"] == File.read_link!("/proc/self/ns/net")
    assert proof["parent"] != proof["child"] and proof["interfaces"] == ["lo"]
    refute proof["default_route"]
    refute proof["ipv6_default_route"]
    assert :ok = Session.close(pid)
    wait(fn -> length(events(ctx, "native_closed")) == length(events(ctx, "native_started")) end)
    assert events(ctx, "fixture_error") == []
    assert events(ctx, "secret_leak") == []
    assert Enum.all?(events(ctx, "secret_scan"), &(&1["passed"] == true))
    assert length(events(ctx, "secret_scan")) == length(events(ctx, "native_started"))

    for started <- events(ctx, "native_started") do
      assert started["binary_sha256"] == @sha
      assert started["no_listener"] and started["no_external_route"]
      assert started["static_credentials_only"]
    end
  end

  defp call(pid, method, params) do
    id = "owned-bedrock-#{System.unique_integer([:positive])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, method, params, id: id)

    result
  end

  defp error(pid, method, params) do
    id = "owned-bedrock-error-#{System.unique_integer([:positive])}"

    assert {:error, %Error{code: :upstream_error, wire: %{"id" => ^id, "error" => failure}}} =
             Session.request(pid, method, params, id: id)

    failure
  end

  defp config_bytes(ctx), do: File.read!(Path.join(ctx.root, "codex/config.toml"))
  defp journal(ctx), do: ctx.root |> Path.join("journal.json") |> File.read!() |> JSON.decode!()
  defp events(ctx, name), do: Enum.filter(journal(ctx)["events"], &(&1["event"] == name))
  defp wait(predicate, remaining \\ 500)
  defp wait(_predicate, 0), do: flunk("Owned Bedrock observation deadline")

  defp wait(predicate, remaining) do
    if value = predicate.() do
      value
    else
      Process.sleep(10)
      wait(predicate, remaining - 1)
    end
  end
end
