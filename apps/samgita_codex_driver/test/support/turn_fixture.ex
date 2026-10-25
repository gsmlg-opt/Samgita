defmodule SamgitaCodexDriver.TurnFixture do
  @moduledoc false
  import ExUnit.Assertions
  import ExUnit.Callbacks

  alias SamgitaCodexDriver.{ModelFixture, NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  def setup(_tags) do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-codex-turn-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    fixture = ModelFixture.start(root, "assistant")
    File.write!(fixture.requests, "[]")

    on_exit(fn ->
      assert :ok = ModelFixture.close(fixture)
    end)

    %{binary: binary, fixture: fixture, root: root}
  end

  def start(context, opts \\ []) do
    args = ["app-server", "--listen", "stdio://"]

    if Keyword.get(opts, :local_plugins, false) do
      config = Path.join(context.fixture.codex_home, "config.toml")

      NativeLaunchFixture.local_plugins_after_initialize(config, fn ->
        start_initialized(context, opts, args)
      end)
    else
      start_initialized(context, opts, NativeLaunchFixture.ordinary_args(args))
    end
  end

  defp start_initialized(context, opts, args) do
    fixture = context.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: context.binary,
             args: args,
             cwd: fixture.workspace,
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_turn_fixture", "version" => "0.1.0"},
               %{"experimentalApi" => Keyword.get(opts, :experimental, true)}
             )

    pid
  end

  def configure_model(context, overrides) do
    # Minimal synthetic ModelInfo, following the pinned openai_models.rs serde test.
    model =
      Map.merge(
        %{
          "slug" => "mock-model",
          "display_name" => "Synthetic turn fixture",
          "supported_reasoning_levels" => [],
          "shell_type" => "unified_exec",
          "visibility" => "list",
          "supported_in_api" => true,
          "priority" => 1,
          "model_messages" => %{
            "instructions_template" => "Synthetic local turn fixture instructions."
          },
          "support_verbosity" => false,
          "truncation_policy" => %{"mode" => "bytes", "limit" => 10_000},
          "experimental_supported_tools" => []
        },
        overrides
      )

    catalog = Path.join(context.fixture.codex_home, "turn-models.json")
    File.write!(catalog, JSON.encode!(%{"models" => [model]}))
    config = Path.join(context.fixture.codex_home, "config.toml")

    File.write!(
      config,
      "model_catalog_json = #{JSON.encode!(catalog)}\n" <> File.read!(config)
    )
  end

  def call(pid, method, params) do
    id = "owned-turn-fixture-#{System.unique_integer([:positive, :monotonic])}"

    case Session.request(pid, method, params, id: id) do
      {:ok, %{"result" => result} = wire} ->
        assert %{"id" => ^id, "result" => ^result} = wire
        result

      {:error, %Error{wire: wire} = error} ->
        flunk("Fixture #{method}: #{inspect({error, wire})}")
    end
  end

  def upstream_error(pid, method, params, opts \\ []) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             Session.request(pid, method, params, opts)

    assert is_integer(error["code"]) and error["code"] < 0
    error
  end

  def thread(context, pid, extra \\ %{}) do
    call(
      pid,
      "thread/start",
      Map.merge(
        %{
          "model" => "mock-model",
          "modelProvider" => "fixture",
          "cwd" => context.fixture.workspace,
          "sandbox" => "read-only",
          "approvalPolicy" => "on-request",
          "ephemeral" => false
        },
        extra
      )
    )["thread"]["id"]
  end

  def start_turn(pid, thread, input, extra \\ %{}) do
    call(pid, "turn/start", Map.merge(%{"threadId" => thread, "input" => input}, extra))[
      "turn"
    ]["id"]
  end

  def finish_turn(pid, thread, turn) do
    events = collect(pid, turn, [], System.monotonic_time(:millisecond) + 20_000)

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    refute Enum.any?(events, &(&1.kind == :server_request)),
           "The assistant-only fixture must not request approval or tools"

    events
  end

  def notification(events, method, predicate \\ fn _ -> true end) do
    Enum.find_value(events, fn event ->
      if event.wire["method"] == method and predicate.(event.wire["params"]),
        do: event.wire["params"]
    end)
  end

  def provider_content(fixture) do
    fixture
    |> ModelFixture.requests()
    |> Enum.flat_map(& &1["input"])
    |> Enum.flat_map(&Map.get(&1, "content", []))
  end

  defp collect(pid, turn, acc, deadline) do
    assert {:ok, events} = Session.drain(pid)
    acc = acc ++ events

    cond do
      notification(acc, "turn/completed", &(&1["turn"]["id"] == turn)) ->
        acc

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("Real turn event deadline: #{inspect(Session.status(pid))}")

      true ->
        assert Session.status(pid).phase == :ready

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected event gap during real turn")
        after
          20 -> :ok
        end

        collect(pid, turn, acc, deadline)
    end
  end
end
