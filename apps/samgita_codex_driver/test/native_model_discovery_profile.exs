defmodule SamgitaCodexDriver.NativeModelDiscoveryProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/offline_model_discovery_fixture.py", __DIR__)

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert :crypto.hash(:sha256, File.read!(binary)) |> Base.encode16(case: :lower) ==
             "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-codex-catalog-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    paths = %{
      root: root,
      home: Path.join(root, "home"),
      codex: Path.join(root, "codex"),
      workspace: Path.join(root, "workspace"),
      tmp: Path.join(root, "tmp")
    }

    Enum.each(Map.values(paths), &File.mkdir_p!/1)
    on_exit(fn -> File.rm_rf!(root) end)
    ctx = Map.put(paths, :binary, binary)
    catalog(ctx, models())
    config(ctx, "fixture")
    ctx
  end

  test "native catalog projects complete rich metadata while filtering hidden and non-API models",
       ctx do
    pid = start(ctx)
    visible = call(pid, "model/list", %{})
    assert visible["nextCursor"] == nil
    assert Enum.map(visible["data"], & &1["id"]) == ["catalog-primary", "catalog-secondary"]
    assert [primary, secondary] = visible["data"]

    assert primary == %{
             "id" => "catalog-primary",
             "model" => "catalog-primary",
             "displayName" => "Primary λ",
             "description" => "Untrusted synthetic model metadata",
             "hidden" => false,
             "isDefault" => true,
             "defaultReasoningEffort" => "focused",
             "supportedReasoningEfforts" => [
               %{"reasoningEffort" => "focused", "description" => "Focused λ"},
               %{"reasoningEffort" => "max", "description" => "Maximum"}
             ],
             "inputModalities" => ["text", "image", "audio"],
             "supportsPersonality" => false,
             "multiAgentVersion" => "v2",
             "modelSpecialty" => "synthetic-specialty",
             "additionalSpeedTiers" => ["fast", "future-speed"],
             "serviceTiers" => [
               %{
                 "id" => "synthetic-tier",
                 "name" => "Synthetic tier",
                 "description" => "Metadata only"
               }
             ],
             "defaultServiceTier" => "synthetic-tier",
             "availableAccessPrograms" => %{
               "cyber" => ["standard", "daybreakBlue", "daybreakRed"]
             },
             "availabilityNux" => %{"message" => "Synthetic availability"},
             "upgrade" => "replacement-model",
             "upgradeInfo" => %{
               "model" => "replacement-model",
               "migrationMarkdown" => "Synthetic migration text",
               "retirementAt" => 1_893_456_000,
               "upgradeCopy" => nil,
               "modelLink" => nil
             }
           }

    assert secondary == minimal("catalog-secondary", false, false)
    all = call(pid, "model/list", %{"includeHidden" => true})

    assert Enum.map(all["data"], & &1["id"]) == [
             "catalog-hidden",
             "catalog-primary",
             "catalog-secondary",
             "catalog-none"
           ]

    assert Enum.map(all["data"], & &1["hidden"]) == [true, false, false, true]
    assert Enum.filter(all["data"], & &1["isDefault"]) == [primary]
    finish(ctx, pid)
  end

  test "native pagination uses filtered offsets and preserves zero limit and end cursor behavior",
       ctx do
    pid = start(ctx)
    all = call(pid, "model/list", %{"includeHidden" => true})["data"]

    assert call(pid, "model/list", %{"includeHidden" => true, "limit" => 0}) == %{
             "data" => [hd(all)],
             "nextCursor" => "1"
           }

    first = call(pid, "model/list", %{"includeHidden" => true, "limit" => 2})
    assert first == %{"data" => Enum.take(all, 2), "nextCursor" => "2"}

    assert call(pid, "model/list", %{
             "includeHidden" => true,
             "limit" => 2,
             "cursor" => first["nextCursor"]
           }) == %{"data" => Enum.drop(all, 2), "nextCursor" => nil}

    assert call(pid, "model/list", %{"includeHidden" => true, "limit" => 4_294_967_295}) == %{
             "data" => all,
             "nextCursor" => nil
           }

    assert call(pid, "model/list", %{"includeHidden" => true, "cursor" => "4"}) == %{
             "data" => [],
             "nextCursor" => nil
           }

    for cursor <- ["invalid", "-1", " 1", "18446744073709551616"] do
      assert error(pid, "model/list", %{"cursor" => cursor}) == %{
               "code" => -32_600,
               "message" => "invalid cursor: #{cursor}"
             }
    end

    assert error(pid, "model/list", %{"cursor" => "3"}) == %{
             "code" => -32_600,
             "message" => "cursor 3 exceeds total models 2"
           }

    assert call(pid, "model/list", %{"cursor" => "2"}) == %{"data" => [], "nextCursor" => nil}
    finish(ctx, pid)
  end

  test "optional null fields and stable negotiation preserve catalog while malformed inputs fail",
       ctx do
    for experimental <- [:absent, false] do
      pid = start(ctx, experimental)
      expected = call(pid, "model/list", %{})

      assert call(pid, "model/list", %{"includeHidden" => nil, "limit" => nil, "cursor" => nil}) ==
               expected

      assert call(pid, "model/list", %{"futureCatalogField" => %{"retain" => "synthetic"}}) ==
               expected

      assert call(pid, "modelProvider/capabilities/read", %{}) == %{
               "imageGeneration" => true,
               "webSearch" => true
             }

      for params <- [
            %{"limit" => -1},
            %{"limit" => 1.5},
            %{"limit" => 4_294_967_296},
            %{"includeHidden" => 1},
            %{"cursor" => 1}
          ] do
        assert {:error, %Error{code: :schema_violation}} =
                 Session.request(pid, "model/list", params)

        assert error(pid, "model/list", params, validation: :wire)["code"] == -32_600
        assert call(pid, "model/list", %{}) == expected
      end

      finish(ctx, pid)
    end
  end

  test "invalid empty config falls back while filtered catalogs preserve native empty cursor policy",
       ctx do
    catalog(ctx, [])
    empty = start(ctx)

    fallback = call(empty, "model/list", %{})
    assert length(fallback["data"]) > 0
    refute Enum.any?(fallback["data"], &String.starts_with?(&1["id"], "catalog-"))

    assert error(empty, "model/list", %{"cursor" => "invalid"}) == %{
             "code" => -32_600,
             "message" => "invalid cursor: invalid"
           }

    assert error(empty, "modelProvider/capabilities/read", %{}) == %{
             "code" => -32_603,
             "message" =>
               "failed to resolve feature override precedence: model_catalog_json path `#{Path.join(ctx.codex, "models.json")}` must contain at least one model"
           }

    assert {:ok, events} = Session.drain(empty)

    assert Enum.any?(events, fn event ->
             event.wire["method"] == "configWarning" and
               event.wire["params"] == %{
                 "summary" => "Invalid configuration; using defaults.",
                 "details" =>
                   "model_catalog_json path `#{Path.join(ctx.codex, "models.json")}` must contain at least one model"
               }
           end)

    catalog(ctx, [base("non-api-only", 0, %{"supported_in_api" => false})])
    finish(ctx, empty)
    filtered = start(ctx)

    assert call(filtered, "model/list", %{"cursor" => "invalid"}) == %{
             "data" => [],
             "nextCursor" => nil
           }

    assert call(filtered, "model/list", %{"includeHidden" => true}) == %{
             "data" => [],
             "nextCursor" => nil
           }

    finish(ctx, filtered)
    catalog(ctx, [base("only-hidden", -1, %{"visibility" => "hide"})])
    hidden = start(ctx)
    assert call(hidden, "model/list", %{}) == %{"data" => [], "nextCursor" => nil}

    assert call(hidden, "model/list", %{"includeHidden" => true}) == %{
             "data" => [minimal("only-hidden", true, true)],
             "nextCursor" => nil
           }

    finish(ctx, hidden)
  end

  test "static catalog is a startup snapshot and cold restart loads new metadata", ctx do
    pid = start(ctx)
    original = call(pid, "model/list", %{"includeHidden" => true})
    catalog(ctx, [base("replacement-catalog", 0, %{})])
    assert call(pid, "model/list", %{"includeHidden" => true}) == original
    finish(ctx, pid)
    cold = start(ctx)

    assert call(cold, "model/list", %{}) == %{
             "data" => [minimal("replacement-catalog", false, true)],
             "nextCursor" => nil
           }

    finish(ctx, cold)
  end

  test "provider capabilities reload local configuration without claiming enabled backend success",
       ctx do
    pid = start(ctx)

    for {provider, expected} <- [
          {"fixture", %{"imageGeneration" => true, "webSearch" => true}},
          {"amazon-bedrock", %{"imageGeneration" => false, "webSearch" => true}},
          {"amazon-bedrock-runtime", %{"imageGeneration" => false, "webSearch" => false}},
          {"fixture", %{"imageGeneration" => true, "webSearch" => true}}
        ] do
      config(ctx, provider)
      assert call(pid, "modelProvider/capabilities/read", %{}) == expected
    end

    config(ctx, "missing-synthetic-provider")

    assert error(pid, "modelProvider/capabilities/read", %{})["message"] =~
             "failed to resolve feature override precedence"

    config(ctx, "fixture")

    assert call(pid, "modelProvider/capabilities/read", %{}) == %{
             "imageGeneration" => true,
             "webSearch" => true
           }

    finish(ctx, pid)
  end

  defp base(id, priority, extra) do
    Map.merge(
      %{
        "slug" => id,
        "display_name" => id,
        "description" => nil,
        "supported_reasoning_levels" => [],
        "shell_type" => "unified_exec",
        "visibility" => "list",
        "supported_in_api" => true,
        "priority" => priority,
        "model_messages" => %{"instructions_template" => "Offline synthetic metadata only"},
        "support_verbosity" => false,
        "truncation_policy" => %{"mode" => "bytes", "limit" => 10_000},
        "experimental_supported_tools" => []
      },
      extra
    )
  end

  defp models do
    [
      base("catalog-secondary", 2, %{}),
      base("catalog-hidden", 0, %{"visibility" => "hide"}),
      base("catalog-none", 4, %{"visibility" => "none"}),
      base("catalog-non-api", 3, %{"supported_in_api" => false}),
      base("catalog-primary", 1, %{
        "display_name" => "Primary λ",
        "description" => "Untrusted synthetic model metadata",
        "default_reasoning_level" => "focused",
        "supported_reasoning_levels" => [
          %{"effort" => "focused", "description" => "Focused λ"},
          %{"effort" => "max", "description" => "Maximum"}
        ],
        "input_modalities" => ["text", "image", "audio"],
        "multi_agent_version" => "v2",
        "model_specialty" => "synthetic-specialty",
        "additional_speed_tiers" => ["fast", "future-speed"],
        "service_tiers" => [
          %{
            "id" => "synthetic-tier",
            "name" => "Synthetic tier",
            "description" => "Metadata only"
          }
        ],
        "default_service_tier" => "synthetic-tier",
        "available_access_programs" => %{"cyber" => ["standard", "daybreak_blue", "daybreak_red"]},
        "availability_nux" => %{"message" => "Synthetic availability"},
        "upgrade" => %{
          "model" => "replacement-model",
          "migration_markdown" => "Synthetic migration text",
          "retirement_at" => "2030-01-01T00:00:00Z"
        }
      })
    ]
  end

  defp minimal(id, hidden, default) do
    %{
      "id" => id,
      "model" => id,
      "displayName" => id,
      "description" => "",
      "hidden" => hidden,
      "isDefault" => default,
      "defaultReasoningEffort" => "none",
      "supportedReasoningEfforts" => [],
      "inputModalities" => ["text", "image"],
      "supportsPersonality" => false,
      "multiAgentVersion" => nil,
      "modelSpecialty" => nil,
      "additionalSpeedTiers" => [],
      "serviceTiers" => [],
      "defaultServiceTier" => nil,
      "availableAccessPrograms" => nil,
      "availabilityNux" => nil,
      "upgrade" => nil,
      "upgradeInfo" => nil
    }
  end

  defp catalog(ctx, models),
    do: File.write!(Path.join(ctx.codex, "models.json"), JSON.encode!(%{"models" => models}))

  defp config(ctx, provider) do
    File.write!(Path.join(ctx.codex, "config.toml"), """
    model = "catalog-primary"
    model_provider = #{JSON.encode!(provider)}
    model_catalog_json = #{JSON.encode!(Path.join(ctx.codex, "models.json"))}
    approval_policy = "never"
    sandbox_mode = "read-only"
    web_search = "disabled"
    [model_providers.fixture]
    name = "Offline synthetic catalog"
    base_url = "http://127.0.0.1:9/v1"
    requires_openai_auth = false
    request_max_retries = 0
    stream_max_retries = 0
    [analytics]
    enabled = false
    [feedback]
    enabled = false
    [features]
    apps = false
    """)
  end

  defp start(ctx, experimental \\ true) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: System.find_executable("python3"),
             args: [@script, "--codex", ctx.binary, "--root", ctx.root],
             cwd: ctx.workspace,
             env: %{
               "HOME" => ctx.home,
               "CODEX_HOME" => ctx.codex,
               "TMPDIR" => ctx.tmp,
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)
    caps = if experimental == :absent, do: %{}, else: %{"experimentalApi" => experimental}

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_offline_model_catalog", "version" => "0.1.0"},
               caps
             )

    pid
  end

  defp finish(ctx, pid) do
    journal =
      Path.join(ctx.root, "offline-model-discovery.json") |> File.read!() |> JSON.decode!()

    assert journal["parent_netns"] != journal["child_netns"]
    assert journal["interfaces"] == ["lo"]
    refute journal["default_route"]
    assert File.read_link!("/proc/#{journal["native_pid"]}/exe") == ctx.binary
    assert call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert Session.status(pid).phase == :ready
    assert :ok = Session.close(pid)

    for key <- ["native_pid", "namespace_owner_pid"],
        do: refute(File.exists?("/proc/#{journal[key]}"))

    refute File.exists?(Path.join(ctx.codex, "auth.json"))
  end

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp error(pid, method, params, opts \\ []) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             Session.request(pid, method, params, opts)

    error
  end
end
