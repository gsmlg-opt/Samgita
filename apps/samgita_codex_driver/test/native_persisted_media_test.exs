defmodule SamgitaCodexDriver.NativePersistedMediaTest do
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
  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
         2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 96, 96, 96, 0,
         0, 0, 4, 0, 1, 246, 23, 56, 85, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>
  # A complete mono PCM WAV containing one silent 16-bit sample at 8000 Hz.
  @wav <<82, 73, 70, 70, 38, 0, 0, 0, 87, 65, 86, 69, 102, 109, 116, 32, 16, 0, 0, 0, 1, 0, 1, 0,
         64, 31, 0, 0, 128, 62, 0, 0, 2, 0, 16, 0, 100, 97, 116, 97, 2, 0, 0, 0, 0, 0>>
  @image "data:image/png;base64," <> Base.encode64(@png)
  @audio "data:audio/wav;base64," <> Base.encode64(@wav)
  @text ~s|{"owned":[null,1,"λ"]}|
  @lookup %{
    "type" => "function",
    "name" => "fixture_lookup",
    "description" => "Owned synthetic media result",
    "inputSchema" => %{
      "type" => "object",
      "properties" => %{"key" => %{"type" => "string"}},
      "required" => ["key"],
      "additionalProperties" => false
    }
  }

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-owned-persisted-media-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "dynamic_tool")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    File.write!(fixture.requests, "[]")
    ctx = %{binary: binary, root: root, fixture: fixture}
    TurnFixture.configure_model(ctx, %{"input_modalities" => ["text", "image", "audio"]})
    config = Path.join(fixture.codex_home, "config.toml")

    File.write!(
      config,
      "cli_auth_credentials_store = \"ephemeral\"\n" <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    ctx
  end

  for success <- [true, false] do
    @success success
    test "native dynamic media success=#{success} survives selective persisted reads and a cold process",
         ctx do
      pid = start(ctx)

      id =
        TurnFixture.thread(ctx, pid, %{
          "historyMode" => "paginated",
          "dynamicTools" => [@lookup]
        })

      turn =
        TurnFixture.start_turn(pid, id, [
          %{
            "type" => "text",
            "text" => "Owned persisted media #{@success}"
          }
        ])

      tool = await_tool(pid, System.monotonic_time(:millisecond) + 10_000)
      assert tool.wire["method"] == "item/tool/call"

      assert tool.wire["params"] == %{
               "threadId" => id,
               "turnId" => turn,
               "callId" => "fixture-call-1",
               "namespace" => nil,
               "tool" => "fixture_lookup",
               "arguments" => %{"key" => "synthetic"}
             }

      assert tool.handle.id == tool.wire["id"]
      assert tool.handle.generation == Session.status(pid).generation
      assert is_reference(tool.handle.reference)
      assert length(ModelFixture.requests(ctx.fixture)) == 1
      assert %{interactions: 1, pending: 0, uncertain: 0} = Session.status(pid)
      content = expected_content()

      assert :ok =
               Session.respond(
                 pid,
                 tool.handle,
                 {:ok,
                  %{
                    "contentItems" => content,
                    "success" => @success
                  }}
               )

      events = TurnFixture.finish_turn(pid, id, turn)

      completed =
        TurnFixture.notification(
          events,
          "item/completed",
          &(&1["item"]["id"] == "fixture-call-1")
        )

      assert completed["threadId"] == id and completed["turnId"] == turn
      assert_dynamic(completed["item"], @success)
      # Output-side oracle: inspect the actual next native Responses request,
      # rather than accepting an echoed item as proof of model-visible output.
      assert [first, continued] = requests = ModelFixture.requests(ctx.fixture)
      refute Enum.any?(first["input"], &(&1["type"] == "function_call_output"))

      assert [%{"call_id" => "fixture-call-1", "output" => provider_output}] =
               Enum.filter(continued["input"], &(&1["type"] == "function_call_output"))

      assert provider_output == [
               %{"type" => "input_text", "text" => @text},
               %{"type" => "input_image", "image_url" => @image, "detail" => "high"},
               %{"type" => "input_audio", "audio_url" => @audio}
             ]

      assert [%{"type" => "input_text"}, %{"image_url" => image}, %{"audio_url" => audio}] =
               provider_output

      assert_media_bytes(image, audio)

      hydrated = call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]
      assert [%{"id" => ^turn, "status" => "completed", "items" => items}] = hydrated["turns"]
      assert [user, dynamic, assistant] = items
      assert user["type"] == "userMessage"
      assert_dynamic(dynamic, @success)
      assert assistant["type"] == "agentMessage"
      assert assistant["text"] == "Deterministic local fixture answer"
      user_id = user["id"]
      assistant_id = assistant["id"]

      query = %{
        "threadId" => id,
        "turnId" => turn,
        "itemIds" => ["owned-absent", "fixture-call-1", "fixture-call-1"]
      }

      assert %{"data" => [entry]} = call(pid, "thread/items/read", query)
      assert Map.fetch!(entry, "turnId") == turn
      assert_dynamic(Map.fetch!(entry, "item"), @success)
      assert is_integer(entry["startedAtMs"]) and entry["startedAtMs"] > 0
      assert is_integer(entry["completedAtMs"]) and entry["completedAtMs"] >= entry["startedAtMs"]
      assert_selectors(pid, query, user_id, assistant_id, @success)
      native_process = call(pid, "server/diagnostics", %{})["process"]["id"]
      assert :ok = Session.close(pid)

      cold = start(ctx)
      refute call(cold, "server/diagnostics", %{})["process"]["id"] == native_process
      assert_unloaded(cold)
      assert %{"data" => [cold_entry]} = call(cold, "thread/items/read", query)
      # Persisted content is checked again against independent known constants,
      # then identity/timing equality checks that this is the original result.
      assert_dynamic(Map.fetch!(cold_entry, "item"), @success)
      assert cold_entry == entry
      assert_selectors(cold, query, user_id, assistant_id, @success)

      assert call(cold, "thread/items/read", %{query | "itemIds" => ["owned-absent"]}) == %{
               "data" => []
             }

      assert_unloaded(cold)
      assert ModelFixture.requests(ctx.fixture) == requests
      assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(cold)
      assert :ok = Session.close(cold)
    end
  end

  defp expected_content,
    do: [
      %{"type" => "inputText", "text" => @text},
      %{"type" => "inputImage", "imageUrl" => @image},
      %{"type" => "inputAudio", "audioUrl" => @audio}
    ]

  defp assert_dynamic(item, success) do
    assert item["type"] == "dynamicToolCall"
    assert item["id"] == "fixture-call-1"
    assert item["namespace"] == nil
    assert item["tool"] == "fixture_lookup"
    assert item["arguments"] == %{"key" => "synthetic"}
    assert item["status"] == if(success, do: "completed", else: "failed")
    assert Map.fetch!(item, "success") == success
    assert Map.fetch!(item, "contentItems") == expected_content()
    assert is_integer(item["durationMs"]) and item["durationMs"] >= 0

    assert [
             %{"type" => "inputText", "text" => @text},
             %{"type" => "inputImage", "imageUrl" => image},
             %{"type" => "inputAudio", "audioUrl" => audio}
           ] = item["contentItems"]

    assert_media_bytes(image, audio)
  end

  defp assert_media_bytes(image, audio) do
    assert "data:image/png;base64," <> png = image
    assert "data:audio/wav;base64," <> wav = audio
    assert Base.decode64!(png) == @png
    assert Base.decode64!(wav) == @wav
  end

  defp assert_selectors(pid, query, user_id, assistant_id, success) do
    for selected <- [[user_id], [assistant_id]] do
      assert %{"data" => [entry]} =
               call(pid, "thread/items/read", %{query | "itemIds" => selected})

      assert entry["item"]["id"] in selected
      refute entry["item"]["type"] == "dynamicToolCall"
    end

    assert %{"data" => rows} =
             call(pid, "thread/items/read", %{
               query
               | "itemIds" => [assistant_id, "fixture-call-1", user_id]
             })

    assert Enum.map(rows, & &1["item"]["id"]) == [user_id, "fixture-call-1", assistant_id]
    assert_dynamic(Enum.at(rows, 1)["item"], success)
  end

  defp assert_unloaded(pid),
    do: assert(call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil})

  defp await_tool(pid, deadline) do
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.wire["method"] == "turn/completed"))

    case Enum.filter(events, &(&1.kind == :server_request)) do
      [tool] ->
        tool

      [] ->
        remaining = deadline - System.monotonic_time(:millisecond)
        assert remaining > 0, "Fixed native dynamic request deadline"

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native media event gap")
        after
          min(remaining, 20) -> :ok
        end

        await_tool(pid, deadline)

      _ ->
        flunk("Unexpected extra native interaction")
    end
  end

  defp start(ctx) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: ctx.binary,
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
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

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_owned_persisted_media", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end
end
