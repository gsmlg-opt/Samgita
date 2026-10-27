defmodule SamgitaCodexDriver.NativeLocalPluginFilterValuesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @provider Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @market "owned-local-filter-values"
  @market_title "Owned local metadata catalog λ"
  @query "  ORBIT!!!  "
  # Literal expected rank, independent of the fixture's reversed declaration order.
  @ranked [
    {"rank-visible", "ORBIT", []},
    {"orbit", "Independent internal exact", []},
    {"orbit-prefix", "Independent prefix", []},
    {"contains-orbit", "Independent substring", []},
    {"rank-keyword", "Independent keyword", ["orbit"]},
    {"rank-substring", "Independent keyword substring", ["xx-orbit-xx"]}
  ]
  @control {"rank-nomatch", "Independent control", []}

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio
    alias SamgitaProtocolCodex.Error

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      case Stdio.send(state, encoded) do
        {:ok, next} ->
          case record(next, :out, encoded) do
            :ok -> {:ok, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          case record_events(next, events) do
            :ok -> {:ok, events, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    defp record_events(state, events) do
      Enum.reduce_while(events, :ok, fn
        {:message, encoded}, :ok ->
          case record(state, :in, encoded) do
            :ok -> {:cont, :ok}
            failure -> {:halt, failure}
          end

        _, :ok ->
          {:cont, :ok}
      end)
    end

    defp record(state, direction, encoded) do
      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(encoded)

        if ledger.count < 128 and size <= 262_144 and ledger.bytes + size <= 1_048_576 do
          entry = %{direction: direction, encoded: encoded, wire: JSON.decode!(encoded)}

          {:ok,
           %{
             count: ledger.count + 1,
             bytes: ledger.bytes + size,
             records: [entry | ledger.records]
           }}
        else
          {{:error, Error.new(:test_capture_overflow)}, ledger}
        end
      end)
    end

    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup tags do
    assert hash(File.read!(@provider)) == @provider_sha
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @provider)

    ctx =
      try do
        TurnFixture.setup(tags)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    assert hash(File.read!(ctx.binary)) == @binary_sha
    TurnFixture.configure_model(ctx, %{})
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    # No configured plugin keys, activation entries or executable plugin content.
    # Keep the exact feature fragment required by local_plugins_after_initialize/2.
    File.write!(config, """
    model = "mock-model"
    model_provider = "fixture"
    model_catalog_json = #{JSON.encode!(Path.join(ctx.fixture.codex_home, "turn-models.json"))}
    cli_auth_credentials_store = "ephemeral"
    check_for_update_on_startup = false
    allow_login_shell = false
    web_search = "disabled"
    chatgpt_base_url = #{JSON.encode!(ctx.fixture.url)}
    openai_base_url = #{JSON.encode!(ctx.fixture.url <> "/v1")}
    [model_providers.fixture]
    name = "Unused owned local metadata witness"
    base_url = #{JSON.encode!(ctx.fixture.url <> "/v1")}
    wire_api = "responses"
    requires_openai_auth = false
    supports_websockets = false
    request_max_retries = 0
    stream_max_retries = 0
    [memories]
    generate_memories = false
    use_memories = false

    [features]
    plugins = true
    remote_plugin = false
    plugin_sharing = false
    apps = false
    shell_snapshot = false
    memories = false
    """)

    File.mkdir!(Path.join(ctx.fixture.workspace, ".git"))
    marketplace = Path.join(ctx.fixture.workspace, ".agents/plugins/marketplace.json")
    File.mkdir_p!(Path.dirname(marketplace))
    rows = Enum.reverse(@ranked ++ [@control])

    entries =
      for {name, _title, _keywords} <- rows do
        %{"name" => name, "source" => %{"source" => "local", "path" => "./#{name}"}}
      end

    File.write!(
      marketplace,
      JSON.encode!(%{
        "name" => @market,
        "interface" => %{"displayName" => @market_title},
        "plugins" => entries
      })
    )

    manifests =
      for {name, title, keywords} <- rows do
        path = Path.join(ctx.fixture.workspace, "#{name}/.codex-plugin/plugin.json")
        File.mkdir_p!(Path.dirname(path))

        File.write!(
          path,
          JSON.encode!(%{
            "name" => name,
            "description" =>
              if(name == "rank-nomatch",
                do: "Only-description-token",
                else: "Owned inert local metadata"
              ),
            "interface" => %{"displayName" => title},
            "keywords" => keywords
          })
        )

        path
      end

    sources =
      [
        config,
        marketplace,
        Path.join(ctx.fixture.codex_home, "turn-models.json"),
        ctx.fixture.requests,
        @provider,
        __ENV__.file
      ] ++
        manifests ++
        Enum.map(
          ~w(model_fixture turn_fixture native_launch_fixture stdio_session_fixture),
          fn name ->
            Path.join(__DIR__, "support/#{name}.ex")
          end
        )

    inputs = Map.new(sources, &{&1, snapshot(&1)})
    capture = start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end})
    assert ModelFixture.requests(ctx.fixture) == []
    Map.merge(ctx, %{config: config, marketplace: marketplace, inputs: inputs, capture: capture})
  end

  test "explicit local catalog and personal search retain metadata across cold replacement; global and workspace exclude ordinary local rows",
       ctx do
    warm = start(ctx)
    warm_native = native_id(ctx, warm)
    warm_results = matrix(ctx, warm)
    assert_retained(ctx, warm)
    close(warm, warm_native)

    cold = start(ctx)
    cold_native = native_id(ctx, cold)
    refute cold_native == warm_native
    assert matrix(ctx, cold) === warm_results
    assert_retained(ctx, cold)
    close(cold, cold_native)
    assert_inputs(ctx.inputs)
    assert ModelFixture.requests(ctx.fixture) == []

    records = Agent.get(ctx.capture, &Enum.reverse(&1.records))

    listings =
      Enum.filter(records, &(&1.direction == :out and &1.wire["method"] == "plugin/list"))

    assert length(listings) == 2

    searches =
      Enum.filter(records, &(&1.direction == :out and &1.wire["method"] == "plugin/search"))

    assert length(searches) == 8

    for scope <- ["personal", "global", "workspace"] do
      assert Enum.count(searches, &(&1.wire["params"]["scope"] == scope)) ==
               if(scope == "personal", do: 4, else: 2)
    end

    for record <- records, do: assert(JSON.decode!(record.encoded) === record.wire)
  end

  defp matrix(ctx, pid) do
    listed =
      call(ctx, pid, "plugin/list", %{
        "cwds" => [ctx.fixture.workspace],
        "marketplaceKinds" => ["local"],
        "forceRefetch" => false
      })

    assert Map.fetch!(listed, "featuredPluginIds") === []
    assert Map.fetch!(listed, "marketplaceLoadErrors") === []
    assert [marketplace] = Map.fetch!(listed, "marketplaces")

    assert Map.take(marketplace, ["name", "path", "interface"]) === %{
             "name" => @market,
             "path" => ctx.marketplace,
             "interface" => %{"displayName" => @market_title}
           }

    listed_metadata =
      marketplace |> Map.fetch!("plugins") |> Enum.map(&metadata/1) |> Enum.sort_by(& &1["id"])

    expected_listed =
      (@ranked ++ [@control])
      |> Enum.map(&expected_metadata(ctx, &1))
      |> Enum.sort_by(& &1["id"])

    assert listed_metadata === expected_listed

    personal = search(ctx, pid, @query, "personal")

    expected =
      for row <- @ranked do
        %{
          "plugin" => expected_metadata(ctx, row),
          "marketplaceName" => @market,
          "marketplacePath" => ctx.marketplace
        }
      end

    observed =
      for row <- Map.fetch!(personal, "data") do
        row
        |> Map.take(["marketplaceName", "marketplacePath"])
        |> Map.put("plugin", metadata(Map.fetch!(row, "plugin")))
      end

    assert observed === expected
    assert Map.fetch!(personal, "nextCursor") === nil
    assert search(ctx, pid, "Only-description-token", "personal") === empty()

    # These are only local-exclusion profiles. No positive built-in global or
    # remote workspace catalog is present, and both empty replies cannot prove
    # a universal global/workspace swap discriminator. Remote kinds remain unrun.
    global = search(ctx, pid, @query, "global")
    workspace = search(ctx, pid, @query, "workspace")
    assert global === empty()
    assert workspace === empty()

    %{
      listed: listed,
      personal: personal,
      global_local_exclusion: global,
      workspace_local_exclusion: workspace
    }
  end

  defp search(ctx, pid, query, scope) do
    call(ctx, pid, "plugin/search", %{
      "searchTerm" => query,
      "scope" => scope,
      "cwds" => [ctx.fixture.workspace]
    })
  end

  defp empty, do: %{"data" => [], "nextCursor" => nil}

  defp metadata(plugin) do
    plugin
    |> Map.take(["id", "name", "keywords", "source"])
    |> Map.put("interface", Map.take(Map.fetch!(plugin, "interface"), ["displayName"]))
  end

  defp expected_metadata(ctx, {name, title, keywords}) do
    %{
      "id" => "#{name}@#{@market}",
      "name" => name,
      "keywords" => keywords,
      "interface" => %{"displayName" => title},
      "source" => %{"type" => "local", "path" => Path.join(ctx.fixture.workspace, name)}
    }
  end

  defp call(ctx, pid, method, params) do
    id = "owned-local-filter-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    records = Agent.get(ctx.capture, &Enum.reverse(&1.records))
    assert [sent, received] = Enum.filter(records, &(&1.wire["id"] == id))
    assert sent.direction == :out
    assert sent.wire === wire
    assert JSON.decode!(sent.encoded) === wire
    assert received.direction == :in
    assert received.wire === response
    assert JSON.decode!(received.encoded) === response
    assert Map.keys(response) |> Enum.sort() == ["id", "result"]
    result
  end

  defp native_id(ctx, pid) do
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native)
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    native
  end

  defp start(ctx) do
    NativeLaunchFixture.local_plugins_after_initialize(ctx.config, fn ->
      {:ok, pid} =
        Session.start_link(
          transport:
            {CaptureStdio,
             [
               capture: ctx.capture,
               executable: ctx.binary,
               args: [
                 "-c",
                 ~s(approval_policy="never"),
                 "-c",
                 ~s(sandbox_mode="danger-full-access"),
                 "-c",
                 "features.recommended_plugins=false",
                 "app-server",
                 "--listen",
                 "stdio://"
               ],
               max_message_bytes: 262_144,
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

      %{connection: connection} = :sys.get_state(pid)
      on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

      assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
               Session.initialize(
                 pid,
                 %{"name" => "owned_local_plugin_filter_values", "version" => "0.1.0"},
                 %{"experimentalApi" => true},
                 timeout_ms: 5_000
               )

      pid
    end)
  end

  defp assert_retained(ctx, pid) do
    assert_inputs(ctx.inputs)
    assert ModelFixture.requests(ctx.fixture) == []
    assert call(ctx, pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert Session.uncertain_operations(pid) == []
    assert {:ok, events} = Session.drain(pid)
    assert length(events) <= 64
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 262_144

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             method == "error" or String.starts_with?(method, "turn/") or
               String.starts_with?(method, "item/")
           end)

    assert_inputs(ctx.inputs)
  end

  defp close(pid, native) do
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")
  end

  defp assert_inputs(inputs) do
    for {path, original} <- inputs, do: assert(snapshot(path) === original)
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
