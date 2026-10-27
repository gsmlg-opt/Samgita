defmodule SamgitaCodexDriver.NativeFsPathValuesTest do
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
  @subject_bytes <<0, 255, 1, 195, 169, 10>>
  @control_bytes <<254, 0, 2, 10>>
  @watch_bytes "Owned native fs path notification λ"
  @typed_request_ids %{
    0 => {"fs/createDirectory", 0},
    1 => {"fs/createDirectory", "0"},
    2 => {"fs/writeFile", 7},
    3 => {"fs/writeFile", "7"},
    4 => {"fs/readFile", 9_007_199_254_740_993},
    7 => {"fs/copy", -1},
    11 => {"fs/watch", 9_223_372_036_854_775_807},
    14 => {"fs/unwatch", -9_223_372_036_854_775_808},
    15 => {"fs/remove", 42},
    16 => {"fs/remove", "42"},
    19 => {"fs/remove", "owned-fs-λ🙂"}
  }

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

      if String.starts_with?(wire["method"] || "", "fs/") do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 32 and byte_size(encoded) <= 4096 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [%{encoded: encoded, wire: wire}]))
          {:ok, next}
        end
      else
        {:error, SamgitaProtocolCodex.Error.new(:test_capture_overflow), state}
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
    stat = System.find_executable("stat")
    assert is_binary(stat) and File.regular?(stat), "BLOCKED_ENV: GNU stat required"
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    capture = start_supervised!({Agent, fn -> [] end})

    Map.merge(ctx, %{
      capture: capture,
      stat: stat,
      config: config,
      config_bytes: File.read!(config)
    })
  end

  test "native direct paths select actual disposable files through copy watch and removal", ctx do
    pid = start(ctx)
    root = ctx.fixture.workspace
    left = Path.join(root, "owned-fs-left-é")
    right = Path.join(root, "owned-fs-right-🙂")
    subject = Path.join(left, "payload-λ.bin")
    control = Path.join(right, "control.bin")
    copied = Path.join(right, "copied-λ.bin")
    watched = Path.join(left, "notification-🙂.txt")
    journal = File.read!(ctx.fixture.requests)

    for path <- [left, right] do
      assert request(ctx, pid, "fs/createDirectory", %{"path" => path, "recursive" => false}) ==
               %{}

      assert File.dir?(path)
    end

    write(ctx, pid, subject, @subject_bytes)
    write(ctx, pid, control, @control_bytes)
    assert_bytes(ctx, pid, subject, @subject_bytes)
    assert_metadata(ctx, pid, subject, true)
    assert_metadata(ctx, pid, left, false)

    assert request(ctx, pid, "fs/copy", %{
             "sourcePath" => subject,
             "destinationPath" => copied,
             "recursive" => false
           }) == %{}

    assert_bytes(ctx, pid, copied, @subject_bytes)
    assert File.read!(subject) == @subject_bytes
    assert File.read!(control) == @control_bytes
    assert_entries(ctx, pid, left, ["payload-λ.bin"])
    assert_entries(ctx, pid, right, ["control.bin", "copied-λ.bin"])

    watch_id = "owned-native-fs-path-watch"

    assert request(ctx, pid, "fs/watch", %{"path" => left, "watchId" => watch_id}) ===
             %{"path" => left}

    refute File.exists?(watched)
    write(ctx, pid, watched, @watch_bytes)
    await_change(pid, watch_id, watched, [], deadline(5000))
    assert_bytes(ctx, pid, watched, @watch_bytes)
    assert File.read!(subject) == @subject_bytes
    assert File.read!(control) == @control_bytes
    assert File.read!(copied) == @subject_bytes
    assert request(ctx, pid, "fs/unwatch", %{"watchId" => watch_id}) == %{}

    for path <- [subject, watched] do
      assert request(ctx, pid, "fs/remove", %{"path" => path}) == %{}
      refute File.exists?(path)
    end

    assert_entries(ctx, pid, left, [])
    assert request(ctx, pid, "fs/remove", %{"path" => left}) == %{}
    refute File.exists?(left)
    assert request(ctx, pid, "fs/remove", %{"path" => copied}) == %{}
    refute File.exists?(copied)
    assert_bytes(ctx, pid, control, @control_bytes)
    assert request(ctx, pid, "fs/remove", %{"path" => control}) == %{}
    refute File.exists?(control)
    assert_entries(ctx, pid, right, [])
    assert request(ctx, pid, "fs/remove", %{"path" => right}) == %{}
    refute File.exists?(right)
    assert_entries(ctx, pid, root, [])

    assert length(Agent.get(ctx.capture, & &1)) == 25
    ids = Agent.get(ctx.capture, &Enum.map(&1, fn entry -> entry.wire["id"] end))
    assert MapSet.size(MapSet.new(ids)) === 25
    assert File.read!(ctx.fixture.requests) == journal
    assert ModelFixture.requests(ctx.fixture) == []
    assert File.read!(ctx.config) == ctx.config_bytes
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert :ok = close(pid)
  end

  defp write(ctx, pid, path, bytes) do
    assert request(ctx, pid, "fs/writeFile", %{
             "path" => path,
             "dataBase64" => Base.encode64(bytes)
           }) == %{}

    assert File.read!(path) === bytes
  end

  defp assert_bytes(ctx, pid, path, expected) do
    assert request(ctx, pid, "fs/readFile", %{"path" => path}) ===
             %{"dataBase64" => Base.encode64(expected)}

    assert File.regular?(path)
    assert File.read!(path) === expected
  end

  defp assert_entries(ctx, pid, path, names) do
    expected =
      Enum.map(Enum.sort(names), fn name ->
        %{"fileName" => name, "isDirectory" => false, "isFile" => true}
      end)

    result = request(ctx, pid, "fs/readDirectory", %{"path" => path})
    assert Enum.sort_by(Map.fetch!(result, "entries"), & &1["fileName"]) === expected
    assert Enum.sort(File.ls!(path)) == Enum.sort(names)
  end

  defp assert_metadata(ctx, pid, path, file?) do
    metadata = request(ctx, pid, "fs/getMetadata", %{"path" => path})
    assert Map.fetch!(metadata, "isFile") == file?
    assert Map.fetch!(metadata, "isDirectory") == not file?
    created = Map.fetch!(metadata, "createdAtMs")
    assert is_integer(created) and created >= 0

    # Differential fixture prerequisite: GNU stat must independently observe birthtime.
    assert {observed, 0} = System.cmd(ctx.stat, ["--printf=%W", "--", path])
    assert {birth_seconds, ""} = observed |> String.trim() |> Integer.parse()

    assert birth_seconds > 0,
           "BLOCKED_ENV: positive GNU stat birthtime required for this differential fixture"

    # SHA-pinned Linux/musl uses Rust 1.95.0 (59807616e1fa2540724bfbac14d7976d7e4a3860).
    # std/sys/fs/unix.rs cfg_has_statx requires Linux/gnu; created() is Unsupported here.
    # Codex maps that to zero: 4016's unavailable branch only; other profiles remain unqualified.
    assert created === 0
  end

  defp request(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = request_id(before, method)
    expected = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, expected)

    assert response["id"] === id
    assert response === %{"id" => id, "result" => result}
    assert [entry] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert entry.wire === expected
    assert entry.encoded === JSON.encode!(expected)
    assert JSON.decode!(entry.encoded) === expected
    result
  end

  defp request_id(index, method) do
    case Map.fetch(@typed_request_ids, index) do
      {:ok, {expected_method, id}} ->
        assert method === expected_method
        id

      :error ->
        "owned-fs-path-#{index}"
    end
  end

  defp await_change(pid, watch_id, path, events, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256, "Native fs path event buffer exceeded its bound"

    found =
      TurnFixture.notification(events, "fs/changed", fn params ->
        params["watchId"] == watch_id and path in params["changedPaths"]
      end)

    if found do
      assert Map.fetch!(found, "watchId") == watch_id
      assert path in Map.fetch!(found, "changedPaths")
    else
      assert Session.status(pid).phase == :ready
      assert System.monotonic_time(:millisecond) < until, "native fs path change deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected event gap during fs path lifecycle")
      after
        10 -> :ok
      end

      await_change(pid, watch_id, path, events, until)
    end
  end

  defp close(pid) do
    native = TurnFixture.call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native)
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")
    :ok
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
               %{"name" => "owned_fs_path_values", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
