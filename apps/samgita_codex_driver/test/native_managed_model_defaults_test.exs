defmodule SamgitaCodexDriver.NativeManagedModelDefaultsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ManagedRequirementsFixture, Session, TurnFixture}
  import ManagedRequirementsFixture, only: [close: 2, assert_idle: 1]
  import TurnFixture, only: [call: 3, upstream_error: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @requirements """
  model_provider = "fixture"
  enforce_residency = "us"
  [windows]
  allowed_sandbox_implementations = ["unelevated"]
  allow_mxc = false
  [features]
  apps = false
  plugins = false
  shell_snapshot = false
  [auto_review]
  required_on_models = ["synthetic-review-only-model"]
  ignore_rules = []
  [models.new_thread]
  model = "synthetic-default-model"
  model_reasoning_effort = "low"
  service_tier = "default"
  """
  @defaults %{
    "model" => "synthetic-default-model",
    "modelReasoningEffort" => "low",
    "serviceTier" => "default"
  }
  @review %{"requiredOnModels" => ["synthetic-review-only-model"], "ignoreRules" => []}
  @features %{"apps" => false, "plugins" => false, "shell_snapshot" => false}

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
    config = Path.join(root, "codex/config.toml")

    File.write!(config, """
    model = "mock-model"
    model_provider = "other_fixture"
    model_reasoning_effort = "medium"
    service_tier = "default"
    approval_policy = "on-request"
    sandbox_mode = "read-only"
    web_search = "disabled"
    cli_auth_credentials_store = "ephemeral"
    chatgpt_base_url = "http://127.0.0.1:9"
    openai_base_url = "http://127.0.0.1:9/v1"
    check_for_update_on_startup = false
    allow_login_shell = false
    [features]
    apps = false
    plugins = false
    recommended_plugins = false
    shell_snapshot = false
    [model_providers.fixture]
    name = "Managed selector nonexecuting fixture"
    base_url = "http://127.0.0.1:9/managed/v1"
    wire_api = "responses"
    requires_openai_auth = false
    supports_websockets = false
    request_max_retries = 0
    stream_max_retries = 0
    [model_providers.other_fixture]
    name = "Unselected nonexecuting fixture"
    base_url = "http://127.0.0.1:9/other/v1"
    wire_api = "responses"
    requires_openai_auth = false
    supports_websockets = false
    request_max_retries = 0
    stream_max_retries = 0
    """)

    %{binary: Path.expand(binary), root: root, config: config, requirements: requirements}
  end

  test "managed requirements expose selected inert model and policy metadata", ctx do
    before = File.read!(ctx.config)
    pid = start(ctx)
    requirements = call(pid, "configRequirements/read", nil)["requirements"]
    assert requirements["modelProvider"] === "fixture"
    assert requirements["models"] === %{"newThread" => @defaults}
    assert requirements["autoReview"] === @review
    assert requirements["featureRequirements"] === @features
    assert requirements["enforceResidency"] === "us"
    assert requirements["allowedWindowsSandboxImplementations"] === ["unelevated"]
    assert File.read!(ctx.requirements) === @requirements
    assert File.read!(ctx.config) === before
    assert_idle(pid)
    close(ctx, pid)
  end

  test "exact provider selector overlays user config while new-thread defaults stay distinct",
       ctx do
    before = File.read!(ctx.config)
    pid = start(ctx)
    response = call(pid, "config/read", %{})
    assert response["config"]["model_provider"] === "fixture"
    refute Map.has_key?(response["origins"], "model_provider")
    assert response["config"]["model"] === "mock-model"
    assert response["config"]["model_reasoning_effort"] === "medium"
    assert response["config"]["service_tier"] === "default"

    assert call(pid, "configRequirements/read", nil)["requirements"]["models"] === %{
             "newThread" => @defaults
           }

    assert File.read!(ctx.config) === before
    assert File.read!(ctx.config) =~ "model_provider = \"other_fixture\""
    assert_idle(pid)
    close(ctx, pid)
  end

  test "managed selector rejects single writes and batches before unrelated edits persist", ctx do
    before = File.read!(ctx.config)
    pid = start(ctx)
    requirements = call(pid, "configRequirements/read", nil)

    for {method, params} <- [
          {"config/value/write", edit("model_provider", "other_fixture")},
          {"config/batchWrite",
           %{
             "edits" => [
               edit("desktop.appearanceTheme", "dark"),
               edit("model_provider", "fixture")
             ]
           }}
        ] do
      error = upstream_error(pid, method, params)
      assert error["code"] == -32_600
      assert error["data"] === %{"config_write_error_code" => "configRequirementReadonly"}

      assert error["message"] ===
               "`model_provider` is managed by requirements and cannot be changed"

      assert File.read!(ctx.config) === before
      assert call(pid, "configRequirements/read", nil) === requirements
      effective = call(pid, "config/read", %{})["config"]
      assert effective["model_provider"] === "fixture"
      refute get_in(effective, ["desktop", "appearanceTheme"])
    end

    assert_idle(pid)
    close(ctx, pid)
  end

  test "explicit requirements reads reload selected defaults and restrictive maps across restart",
       ctx do
    before = File.read!(ctx.config)
    pid = start(ctx)
    original = call(pid, "configRequirements/read", nil)["requirements"]

    changed =
      @requirements
      |> String.replace("synthetic-default-model", "synthetic-next-model")
      |> String.replace("model_reasoning_effort = \"low\"", "model_reasoning_effort = \"high\"")
      |> String.replace(
        "required_on_models = [\"synthetic-review-only-model\"]",
        "required_on_models = [\"synthetic-review-only-model\", \"synthetic-next-review-model\"]"
      )
      |> String.replace(
        "shell_snapshot = false",
        "shell_snapshot = false\nrecommended_plugins = false"
      )

    File.write!(ctx.requirements, changed)

    expected =
      original
      |> Map.put("models", %{
        "newThread" => %{
          @defaults
          | "model" => "synthetic-next-model",
            "modelReasoningEffort" => "high"
        }
      })
      |> Map.put("autoReview", %{
        @review
        | "requiredOnModels" => ["synthetic-review-only-model", "synthetic-next-review-model"]
      })
      |> Map.put("featureRequirements", Map.put(@features, "recommended_plugins", false))

    assert call(pid, "configRequirements/read", nil)["requirements"] === expected
    assert File.read!(ctx.config) === before
    assert call(pid, "config/read", %{})["config"]["model"] === "mock-model"
    assert_idle(pid)
    close(ctx, pid)

    restarted = start(ctx)
    assert call(restarted, "configRequirements/read", nil)["requirements"] === expected
    assert File.read!(ctx.config) === before
    assert File.read!(ctx.requirements) === changed
    assert_idle(restarted)
    close(ctx, restarted)
  end

  test "managed reasoning effort preserves custom strings and rejects malformed types before recovery",
       ctx do
    before = File.read!(ctx.config)
    pid = start(ctx)
    baseline = call(pid, "configRequirements/read", nil)

    try do
      custom = "not-an-effort"

      File.write!(
        ctx.requirements,
        String.replace(
          @requirements,
          "model_reasoning_effort = \"low\"",
          "model_reasoning_effort = #{inspect(custom)}"
        )
      )

      expected =
        put_in(baseline, ["requirements", "models", "newThread", "modelReasoningEffort"], custom)

      assert call(pid, "configRequirements/read", nil) === expected
      assert File.read!(ctx.config) === before
      assert_idle(pid)

      File.write!(
        ctx.requirements,
        String.replace(
          @requirements,
          "model_reasoning_effort = \"low\"",
          "model_reasoning_effort = 17"
        )
      )

      error = upstream_error(pid, "configRequirements/read", nil)
      assert error["code"] == -32_603
      assert error["message"] =~ "failed to read configuration layers:"
      assert error["message"] =~ "/etc/codex/requirements.toml"
      assert error["message"] =~ "failed to parse requirements layer"
      assert error["message"] =~ "expected a string"
      assert Session.status(pid).phase == :ready
      assert File.read!(ctx.config) === before
    after
      File.write!(ctx.requirements, @requirements)
    end

    assert call(pid, "configRequirements/read", nil) === baseline
    assert_idle(pid)
    close(ctx, pid)
  end

  defp edit(path, value), do: %{"keyPath" => path, "value" => value, "mergeStrategy" => "replace"}

  defp start(ctx),
    do: ManagedRequirementsFixture.start(ctx, "owned_managed_model_defaults")
end
