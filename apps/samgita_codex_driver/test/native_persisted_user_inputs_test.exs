defmodule SamgitaCodexDriver.NativePersistedUserInputsTest do
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
  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
         2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 96, 96, 96, 0,
         0, 0, 4, 0, 1, 246, 23, 56, 85, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>
  # Complete mono PCM WAV: one silent 16-bit sample at 8000 Hz.
  @wav <<82, 73, 70, 70, 38, 0, 0, 0, 87, 65, 86, 69, 102, 109, 116, 32, 16, 0, 0, 0, 1, 0, 1, 0,
         64, 31, 0, 0, 128, 62, 0, 0, 2, 0, 16, 0, 100, 97, 116, 97, 2, 0, 0, 0, 0, 0>>
  @image "data:image/png;base64," <> Base.encode64(@png)
  @audio "data:audio/wav;base64," <> Base.encode64(@wav)

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha
    ctx = TurnFixture.setup(tags)

    TurnFixture.configure_model(ctx, %{
      "input_modalities" => ["text", "image", "audio"],
      "supports_image_detail_original" => true
    })

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      "cli_auth_credentials_store = \"ephemeral\"\n" <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\n" <>
        "shell_snapshot = false\nbrowser_use = false\ncomputer_use = false\n"
    )

    File.mkdir!(Path.join(ctx.root, "tmp"))
    ctx
  end

  for {source, inline, expected_inline, local_detail} <- [
        {:url, %{"type" => "image", "url" => @image, "detail" => "auto"},
         %{"type" => "input_image", "image_url" => @image, "detail" => "auto"}, "high"},
        {:file_id,
         %{"type" => "image", "fileId" => "file-owned-persisted-163", "detail" => "low"},
         %{"type" => "input_image", "file_id" => "file-owned-persisted-163", "detail" => "low"},
         "original"}
      ] do
    @source source
    @inline inline
    @expected_inline expected_inline
    @local_detail local_detail
    test "native persisted #{@source} image and typed inputs retain exact content after cold start",
         ctx do
      source = @source
      label = Atom.to_string(source)
      image_path = Path.join(ctx.fixture.workspace, "owned pixel #{label}.png")
      audio_path = Path.join(ctx.fixture.workspace, "owned silence #{label}.wav")
      skill_name = "owned-persisted-#{label}"
      skill_path = Path.join([ctx.fixture.codex_home, "skills", skill_name, "SKILL.md"])
      sentinel = "OWNED_PERSISTED_SKILL_#{label}_163"

      skill_bytes =
        "---\nname: #{skill_name}\ndescription: Inert local persistence fixture\n---\n\n#{sentinel}\n"

      File.write!(image_path, @png)
      File.write!(audio_path, @wav)
      File.mkdir_p!(Path.dirname(skill_path))
      File.write!(skill_path, skill_bytes)
      owned_files = [{image_path, @png}, {audio_path, @wav}, {skill_path, skill_bytes}]

      local_detail = @local_detail
      mention_path = "app://samgita-owned-absent-#{label}"

      input = [
        %{"type" => "text", "text" => "Owned typed inputs #{label}", "text_elements" => []},
        @inline,
        %{"type" => "localImage", "path" => image_path, "detail" => local_detail},
        %{"type" => "audio", "url" => @audio},
        %{"type" => "localAudio", "path" => audio_path},
        %{"type" => "skill", "name" => skill_name, "path" => skill_path},
        %{"type" => "mention", "name" => "Owned absent mention #{label}", "path" => mention_path}
      ]

      pid = start(ctx)

      assert [%{"skills" => skills}] =
               call(pid, "skills/list", %{"cwds" => [ctx.fixture.workspace]})["data"]

      assert Enum.any?(
               skills,
               &(&1["name"] == skill_name and &1["path"] == skill_path and &1["enabled"])
             )

      id = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})
      client_id = "owned-persisted-client-#{label}"
      turn = TurnFixture.start_turn(pid, id, input, %{"clientUserMessageId" => client_id})
      events = TurnFixture.finish_turn(pid, id, turn)
      began = user_event(events, "item/started")
      ended = user_event(events, "item/completed")
      item_id = Map.fetch!(ended["item"], "id")
      assert is_binary(item_id) and byte_size(item_id) > 0

      expected_item = %{
        "type" => "userMessage",
        "id" => item_id,
        "clientId" => client_id,
        "content" => input
      }

      for event <- [began, ended] do
        assert event["threadId"] == id and event["turnId"] == turn
        assert event["item"] == expected_item
      end

      started = Map.fetch!(began, "startedAtMs")
      completed = Map.fetch!(ended, "completedAtMs")
      assert is_integer(started) and started > 0
      assert is_integer(completed) and completed >= started

      expected_entry = %{
        "turnId" => turn,
        "item" => expected_item,
        "startedAtMs" => started,
        "completedAtMs" => completed
      }

      query = %{"threadId" => id, "turnId" => turn, "itemIds" => [item_id]}
      # Explicit native flush/projection barrier; its content is not our oracle.
      hydrated = call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]
      assert hydrated["id"] == id
      assert [%{"id" => ^turn, "status" => "completed"}] = hydrated["turns"]
      assert_selected(pid, query, expected_entry)

      # Output-side checks inspect the one captured local model request.
      assert [request] = ModelFixture.requests(ctx.fixture)

      content =
        for message <- request["input"], entry <- Map.get(message, "content", []), do: entry

      assert Enum.filter(content, &(&1["type"] == "input_image")) == [
               @expected_inline,
               %{"type" => "input_image", "image_url" => @image, "detail" => local_detail}
             ]

      assert Enum.filter(content, &(&1["type"] == "input_audio")) == [
               %{"type" => "input_audio", "audio_url" => @audio},
               %{"type" => "input_audio", "audio_url" => @audio}
             ]

      texts = Enum.map_join(content, "\n", &Map.get(&1, "text", ""))
      assert [_before, _after] = String.split(texts, sentinel)
      refute texts =~ mention_path
      assert_owned_files(owned_files)
      assert_idle(pid)
      process_id = call(pid, "server/diagnostics", %{})["process"]["id"]
      assert :ok = Session.close(pid)

      cold = start(ctx)
      refute call(cold, "server/diagnostics", %{})["process"]["id"] == process_id
      assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
      # No resume/hydration or turn request: read original durable item directly.
      assert_selected(cold, query, expected_entry)
      assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
      assert ModelFixture.requests(ctx.fixture) == [request]
      assert_owned_files(owned_files)
      assert_idle(cold)
      assert :ok = Session.close(cold)
    end
  end

  defp assert_selected(pid, query, entry) do
    assert call(pid, "thread/items/read", query) == %{"data" => [entry]}
    [item_id] = query["itemIds"]

    assert call(pid, "thread/items/read", %{
             query
             | "itemIds" => ["owned-missing", item_id, item_id]
           }) == %{"data" => [entry]}

    assert call(pid, "thread/items/read", %{query | "itemIds" => ["owned-missing"]}) == %{
             "data" => []
           }

    assert call(pid, "thread/items/read", %{query | "turnId" => "owned-absent-turn"}) == %{
             "data" => []
           }
  end

  defp user_event(events, method) do
    assert [event] =
             for(
               event <- events,
               event.wire["method"] == method,
               event.wire["params"]["item"]["type"] == "userMessage",
               do: event.wire["params"]
             )

    event
  end

  defp assert_owned_files(files) do
    for {path, bytes} <- files, do: assert(File.read!(path) === bytes)
  end

  defp assert_idle(pid) do
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(pid)
  end

  defp start(ctx) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: Path.expand(ctx.binary),
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
             cwd: fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "SHELL" => Path.join(fixture.bin, "sh"),
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
               %{"name" => "samgita_persisted_user_inputs", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end
end
