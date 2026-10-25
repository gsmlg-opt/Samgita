defmodule SamgitaCodexDriver.NativeSuppliedHistoryInputsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaCodexDriver.Transport.Stdio
  import TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @marker "Owned genuine supplied-history media 163"
  @followup "Owned continuation after supplied history 163"
  @answer "Deterministic local fixture answer"
  @file_id "file-owned-history-import-163"
  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
         2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 96, 96, 96, 0,
         0, 0, 4, 0, 1, 246, 23, 56, 85, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>
  @wav <<82, 73, 70, 70, 38, 0, 0, 0, 87, 65, 86, 69, 102, 109, 116, 32, 16, 0, 0, 0, 1, 0, 1, 0,
         64, 31, 0, 0, 128, 62, 0, 0, 2, 0, 16, 0, 100, 97, 116, 97, 2, 0, 0, 0, 0, 0>>
  @image "data:image/png;base64," <> Base.encode64(@png)
  @audio "data:audio/wav;base64," <> Base.encode64(@wav)
  @raw_content [
    %{"type" => "input_text", "text" => @marker},
    %{"type" => "input_image", "image_url" => @image, "detail" => "auto"},
    %{"type" => "input_image", "file_id" => @file_id, "detail" => "low"},
    %{"type" => "input_audio", "audio_url" => @audio}
  ]
  @assistant_content [%{"type" => "output_text", "text" => @answer}]
  @max_rollout_bytes 4_194_304
  @max_line_bytes 262_144

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert binary_hash(binary) == @binary_sha

    # Select the existing normal provider fixture even if a previous profile has
    # configured an alternate script. Restore the environment immediately.
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    ctx =
      try do
        TurnFixture.setup(tags)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    TurnFixture.configure_model(ctx, %{
      "input_modalities" => ["text", "image", "audio"],
      "supports_image_detail_original" => true
    })

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\n" <>
        "shell_snapshot = false\nbrowser_use = false\ncomputer_use = false\n"
    )

    File.mkdir!(Path.join(ctx.root, "tmp"))

    Map.put(ctx, :unchanged_files, [
      {config, File.read!(config)},
      {Path.join(ctx.fixture.codex_home, "turn-models.json"),
       File.read!(Path.join(ctx.fixture.codex_home, "turn-models.json"))},
      {@script, File.read!(@script)}
    ])
  end

  test "unstable native history import preserves genuine raw media and message metadata", ctx do
    source = start(ctx)
    source_process = native_process(source)

    source_id =
      TurnFixture.thread(ctx, source, %{
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access",
        "historyMode" => "legacy"
      })

    started = System.system_time(:microsecond) / 1_000_000

    source_turn =
      TurnFixture.start_turn(source, source_id, [
        %{"type" => "text", "text" => @marker, "text_elements" => []},
        %{"type" => "image", "url" => @image, "detail" => "auto"},
        %{"type" => "image", "fileId" => @file_id, "detail" => "low"},
        %{"type" => "audio", "url" => @audio}
      ])

    finish_turn(source, source_id, source_turn)
    saved_source = read_thread(source, source_id)
    source_path = Map.fetch!(saved_source, "path")
    assert Map.fetch!(saved_source, "id") == source_id
    finished = System.system_time(:microsecond) / 1_000_000
    assert [first_request] = requests(ctx)
    assert_idle(source)
    assert :ok = Session.close(source)
    assert_gone(source_process)

    {source_bytes, source_payloads} = rollout(ctx, source_path)
    [user, assistant] = captured_history(source_payloads)
    assert_message(user, "user", @raw_content, source_turn, started, finished)
    assert_message(assistant, "assistant", @assistant_content, source_turn, started, finished)
    assert Map.fetch!(assistant, "id") == "fixture-message-1"
    refute Map.fetch!(user, "id") == Map.fetch!(assistant, "id")
    history = [user, assistant]

    # The only raw ResponseItem client input in the pin is explicitly unstable
    # thread/resume.history. These are native-created payloads, never fabricated
    # rollout records or manually completed schema maps.
    cold = start(ctx)
    cold_process = native_process(cold)
    refute cold_process == source_process
    assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}

    resumed =
      call(cold, "thread/resume", %{
        "threadId" => source_id,
        "history" => history,
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access"
      })["thread"]

    imported_id = Map.fetch!(resumed, "id")
    assert is_binary(imported_id) and imported_id != ""
    refute imported_id == source_id
    assert Map.fetch!(resumed, "preview") == @marker
    assert Map.fetch!(resumed, "status") == %{"type" => "idle"}

    saved_import = read_thread(cold, imported_id)
    imported_path = Map.fetch!(saved_import, "path")
    refute imported_path == source_path
    assert_imported_history(ctx, imported_path, history)
    assert requests(ctx) == [first_request]
    assert File.read!(source_path) === source_bytes

    next_turn =
      TurnFixture.start_turn(cold, imported_id, [
        %{"type" => "text", "text" => @followup, "text_elements" => []}
      ])

    finish_turn(cold, imported_id, next_turn)
    assert Map.fetch!(read_thread(cold, imported_id), "id") == imported_id
    assert [^first_request, continued] = requests(ctx)
    assert_provider_history(continued)
    assert_imported_history(ctx, imported_path, history)
    assert File.read!(source_path) === source_bytes
    assert_unchanged(ctx)
    assert_idle(cold)
    assert :ok = Session.close(cold)
    assert_gone(cold_process)

    # Closing the importing native must also preserve the original source file.
    assert File.read!(source_path) === source_bytes
    assert_unchanged(ctx)
  end

  defp captured_history(payloads) do
    assert [user] =
             Enum.filter(payloads, fn item ->
               item["type"] == "message" and item["role"] == "user" and
                 Enum.any?(Map.get(item, "content", []), fn part ->
                   part == %{"type" => "input_text", "text" => @marker}
                 end)
             end)

    assert [assistant] =
             Enum.filter(payloads, fn item ->
               item["type"] == "message" and item["role"] == "assistant" and
                 item["id"] == "fixture-message-1"
             end)

    [user, assistant]
  end

  defp assert_message(item, role, content, turn, started, finished) do
    assert Map.fetch!(item, "type") == "message"
    assert Map.fetch!(item, "role") == role
    assert Map.fetch!(item, "content") === content
    assert is_binary(Map.fetch!(item, "id")) and byte_size(item["id"]) > 0
    metadata = Map.fetch!(item, "internal_chat_message_metadata_passthrough")
    assert is_map(metadata)
    assert Map.fetch!(metadata, "turn_id") == turn

    case role do
      "user" ->
        created = Map.fetch!(metadata, "create_time")
        assert is_number(created) and created >= started and created <= finished

        assert metadata === %{
                 "turn_id" => turn,
                 "create_time" => created,
                 "content_item_kinds" => ["user.text", "user.image", "user.image", "user.audio"]
               }

      "assistant" ->
        # models.rs:set_create_time_if_missing stamps Message only for user or
        # developer roles. Native assistant metadata has no creation timestamp;
        # annotated_content.rs classifies the provider's untyped text as unknown.
        assert metadata === %{"turn_id" => turn, "content_item_kinds" => ["unknown"]}
        refute Map.has_key?(metadata, "create_time")
    end
  end

  defp assert_imported_history(ctx, path, history) do
    {_bytes, payloads} = rollout(ctx, path)
    assert captured_history(payloads) === history

    for item <- history do
      assert Enum.count(payloads, &(&1["id"] == item["id"])) == 1
      assert Enum.count(payloads, &(&1 === item)) == 1
    end
  end

  defp assert_provider_history(request) do
    # The pin strips passthrough metadata from non-OpenAI provider copies
    # (core/src/client.rs), so provider content and persisted metadata have
    # distinct oracles. Do not expect the provider copy to echo whole raw maps.
    input = Map.fetch!(request, "input")
    assert Enum.count(input, &(&1["role"] == "user" and &1["content"] === @raw_content)) == 1

    assert Enum.count(
             input,
             &(&1["role"] == "assistant" and &1["content"] === @assistant_content)
           ) == 1

    assert Enum.count(input, fn item ->
             item["role"] == "user" and
               item["content"] === [%{"type" => "input_text", "text" => @followup}]
           end) == 1

    metadata =
      request
      |> Map.fetch!("client_metadata")
      |> Map.fetch!("x-codex-turn-metadata")
      |> JSON.decode!()

    assert Map.fetch!(metadata, "history_initialization") == "supplied_history"
  end

  defp rollout(ctx, path) do
    assert is_binary(path)
    expanded = Path.expand(path)
    assert String.starts_with?(expanded, Path.expand(ctx.fixture.codex_home) <> "/")
    assert %{type: :regular, size: size} = File.stat!(expanded)
    assert size > 0 and size <= @max_rollout_bytes
    bytes = File.read!(expanded)
    assert byte_size(bytes) == size
    lines = String.split(bytes, "\n", trim: true)
    assert length(lines) <= 2_048

    payloads =
      for line <- lines,
          _ = assert(byte_size(line) <= @max_line_bytes),
          row = JSON.decode!(line),
          row["type"] == "response_item",
          do: Map.fetch!(row, "payload")

    assert payloads != []
    {bytes, payloads}
  end

  defp requests(ctx) do
    assert File.stat!(ctx.fixture.requests).size <= @max_rollout_bytes
    ModelFixture.requests(ctx.fixture)
  end

  defp read_thread(pid, id),
    do: call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]

  defp finish_turn(pid, thread, turn) do
    events = collect(pid, turn, [], System.monotonic_time(:millisecond) + 20_000)

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             TurnFixture.notification(events, "turn/completed", &(&1["turn"]["id"] == turn))
  end

  defp collect(pid, turn, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 1_048_576

    if TurnFixture.notification(events, "turn/completed", &(&1["turn"]["id"] == turn)) do
      events
    else
      assert System.monotonic_time(:millisecond) < deadline, "Supplied-history turn deadline"
      assert Session.status(pid).phase == :ready

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected supplied-history event gap")
      after
        10 -> :ok
      end

      collect(pid, turn, events, deadline)
    end
  end

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert Session.uncertain_operations(pid) == []
  end

  defp assert_unchanged(ctx) do
    for {path, bytes} <- ctx.unchanged_files, do: assert(File.read!(path) === bytes)
  end

  defp native_process(pid) do
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert binary_hash("/proc/#{native}/exe") == @binary_sha
    native
  end

  defp binary_hash(path),
    do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)

  defp assert_gone(native, remaining \\ 100) do
    if File.exists?("/proc/#{native}") do
      assert remaining > 0, "Owned supplied-history process #{native} survived cleanup"
      Process.sleep(10)
      assert_gone(native, remaining - 1)
    else
      :ok
    end
  end

  defp start(ctx) do
    f = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        max_events: 256,
        max_event_bytes: 1_048_576,
        max_message_bytes: 1_048_576,
        transport:
          {Stdio,
           [
             executable: Path.expand(ctx.binary),
             args:
               NativeLaunchFixture.ordinary_args([
                 "-c",
                 ~s(approval_policy="never"),
                 "-c",
                 ~s(sandbox_mode="danger-full-access"),
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: f.workspace,
             inherit_env: [],
             env: %{
               "HOME" => f.home,
               "CODEX_HOME" => f.codex_home,
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => f.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "SHELL" => Path.join(f.bin, "sh"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_supplied_history_inputs", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end
end
