defmodule SamgitaCodexDriver.NativeFeatureStageValuesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @catalog_count 175
  # Independent literals and indices from the immutable FEATURES declaration.
  # No expected stage, metadata or ordering comes from a response under test.
  @representatives [
    {13,
     %{
       "name" => "login_shell_package_path",
       "stage" => "beta",
       "displayName" => "Bundled tools in login shells",
       "description" =>
         "Keep bundled tools such as ripgrep available when login shell startup resets PATH.",
       "announcement" => "",
       "enabled" => false,
       "defaultEnabled" => false
     }},
    {17,
     %{
       "name" => "cwd_relative_turn_diffs",
       "stage" => "underDevelopment",
       "displayName" => nil,
       "description" => nil,
       "announcement" => nil,
       "enabled" => false,
       "defaultEnabled" => false
     }},
    {5,
     %{
       "name" => "view_image",
       "stage" => "stable",
       "displayName" => nil,
       "description" => nil,
       "announcement" => nil,
       "enabled" => true,
       "defaultEnabled" => true
     }},
    {2,
     %{
       "name" => "transcript_v2",
       "stage" => "deprecated",
       "displayName" => nil,
       "description" => nil,
       "announcement" => nil,
       "enabled" => false,
       "defaultEnabled" => false
     }},
    {3,
     %{
       "name" => "undo",
       "stage" => "removed",
       "displayName" => nil,
       "description" => nil,
       "announcement" => nil,
       "enabled" => false,
       "defaultEnabled" => false
     }}
  ]

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      wire = JSON.decode!(encoded)

      if wire["method"] == "experimentalFeature/list" do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 64 and byte_size(encoded) <= 4096 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [wire]))
          {:ok, next}
        end
      else
        {:error, Error.new(:test_capture_overflow), state}
      end
    end

    @impl true
    def handle_info(message, state), do: Stdio.handle_info(message, state)
    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup tags do
    ctx = TurnFixture.setup(tags)
    assert hash(File.read!(ctx.binary)) == @binary_sha
    TurnFixture.configure_model(ctx, %{})
    capture = start_supervised!({Agent, fn -> [] end})
    Map.put(ctx, :capture, capture)
  end

  test "native stages retain exact metadata with nondefault harmless catalog values", ctx do
    qualify(ctx, false, true)
  end

  test "native stages retain exact metadata with default harmless catalog values", ctx do
    qualify(ctx, true, false)
  end

  defp qualify(ctx, view_image, relative_diffs) do
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    bytes =
      File.read!(config) <>
        "\n[features]\nview_image = #{view_image}\ncwd_relative_turn_diffs = #{relative_diffs}\n"

    File.write!(config, bytes)
    expected = expected_features(view_image, relative_diffs)
    pid = start(ctx)
    assert_catalog(ctx, pid, expected)
    assert File.read!(config) === bytes
    assert_functional_state(ctx, pid)
    original = native_id(pid)
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{original}")
    cold = start(ctx)
    assert native_id(cold) != original
    assert_catalog(ctx, cold, expected)
    assert File.read!(config) === bytes
    assert_functional_state(ctx, cold)
    replacement = native_id(cold)
    assert :ok = Session.close(cold)
    refute File.exists?("/proc/#{replacement}")
    assert ModelFixture.requests(ctx.fixture) == []
    assert length(Agent.get(ctx.capture, & &1)) == 16
  end

  defp expected_features(view_image, relative_diffs) do
    Enum.map(@representatives, fn {index, feature} ->
      enabled =
        case feature["name"] do
          "view_image" -> view_image
          "cwd_relative_turn_diffs" -> relative_diffs
          _ -> feature["enabled"]
        end

      {index, Map.put(feature, "enabled", enabled)}
    end)
  end

  defp assert_catalog(ctx, pid, expected) do
    for params <- [%{}, %{"cursor" => nil, "limit" => nil, "threadId" => nil}] do
      result = request(ctx, pid, params)
      assert Map.fetch!(result, "nextCursor") == nil
      assert length(result["data"]) == @catalog_count

      for {_index, feature} <- expected do
        matching = Enum.filter(result["data"], &(&1["name"] == feature["name"]))
        assert matching === [feature]
      end
    end

    for {index, feature} <- expected do
      assert request(ctx, pid, %{"cursor" => to_string(index), "limit" => 1}) === %{
               "data" => [feature],
               "nextCursor" => to_string(index + 1)
             }
    end

    assert request(ctx, pid, %{"cursor" => to_string(@catalog_count), "limit" => 1}) === %{
             "data" => [],
             "nextCursor" => nil
           }
  end

  defp request(ctx, pid, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-feature-stage-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, "experimentalFeature/list", params, id: id)

    assert [wire] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert wire === %{"id" => id, "method" => "experimentalFeature/list", "params" => params}
    result
  end

  defp assert_functional_state(ctx, pid) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert call(pid, "thread/loaded/list", %{})["data"] == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
  end

  defp native_id(pid) do
    id = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(id)
    assert hash(File.read!("/proc/#{id}/exe")) == @binary_sha
    id
  end

  defp start(ctx) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {CaptureStdio,
           [
             capture: ctx.capture,
             executable: ctx.binary,
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
             cwd: fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "TMPDIR" => ctx.root,
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    %{transport: CaptureStdio, connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_feature_stage_values", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
