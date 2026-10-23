defmodule SamgitaCodexDriver.TurnAttachmentTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.TurnFixture
  import SamgitaCodexDriver.TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000

  setup {TurnFixture, :setup}

  test "audio canonicalizes inline MIME and replaces remote URIs while preserving user inputs",
       context do
    configure_model(context, %{"input_modalities" => ["text", "image", "audio"]})
    pid = start(context)
    thread = thread(context, pid)

    urls = [
      "data:audio/x-wav;base64,YXVkaW8=",
      context.fixture.url <> "/synthetic.mp3?clip=1#part"
    ]

    input = Enum.map(urls, &%{"type" => "audio", "url" => &1})
    turn = start_turn(pid, thread, [text("Synthetic audio attachment only") | input])
    events = finish_turn(pid, thread, turn)

    content = provider_content(context.fixture)
    assert audio_urls(content) == ["data:audio/wav;base64,YXVkaW8="]

    assert %{
             "type" => "input_text",
             "text" => "audio content omitted because it could not be processed"
           } in content

    assert_user_inputs(events, thread, turn, input)
  end

  test "local audio constructs data URLs for every supported MIME and preserves paths", context do
    configure_model(context, %{"input_modalities" => ["text", "image", "audio"]})

    formats = [
      {"wav", "audio/wav"},
      {"MP3", "audio/mpeg"},
      {"m4a", "audio/mp4"},
      {"webm", "audio/webm"},
      {"ogg", "audio/ogg"}
    ]

    input =
      Enum.map(formats, fn {extension, _mime} ->
        path = Path.join(context.fixture.workspace, "synthetic clip.#{extension}")
        File.write!(path, "synthetic audio bytes")
        %{"type" => "localAudio", "path" => path}
      end)

    pid = start(context)
    thread = thread(context, pid)
    turn = start_turn(pid, thread, [text("Synthetic local attachments only") | input])
    events = finish_turn(pid, thread, turn)
    content = provider_content(context.fixture)
    encoded = Base.encode64("synthetic audio bytes")

    assert audio_urls(content) ==
             Enum.map(formats, fn {_extension, mime} -> "data:#{mime};base64,#{encoded}" end)

    for %{"path" => path} <- input do
      assert Enum.any?(content, &String.contains?(&1["text"] || "", path))
    end

    assert_user_inputs(events, thread, turn, input)
  end

  test "a model without audio support receives the upstream omitted-audio fallback", context do
    pid = start(context)
    thread = thread(context, pid)
    input = %{"type" => "audio", "url" => "data:audio/wav;base64,YXVkaW8="}
    turn = start_turn(pid, thread, [text("Synthetic unsupported-model audio only"), input])
    events = finish_turn(pid, thread, turn)
    content = provider_content(context.fixture)

    assert audio_urls(content) == []

    assert Enum.any?(content, fn item ->
             String.contains?(
               item["text"] || "",
               "audio content omitted because you do not support audio input"
             )
           end)

    assert_user_inputs(events, thread, turn, [input])
  end

  test "missing and unsupported local audio produce upstream text fallbacks", context do
    missing = Path.join(context.fixture.workspace, "missing.wav")
    unsupported = Path.join(context.fixture.workspace, "synthetic.flac")
    File.write!(unsupported, "synthetic audio bytes")

    input = [
      %{"type" => "localAudio", "path" => missing},
      %{"type" => "localAudio", "path" => unsupported}
    ]

    pid = start(context)
    thread = thread(context, pid)
    turn = start_turn(pid, thread, [text("Synthetic attachment errors only") | input])
    events = finish_turn(pid, thread, turn)
    content = provider_content(context.fixture)

    assert audio_urls(content) == []

    assert Enum.any?(content, fn item ->
             String.starts_with?(
               item["text"] || "",
               "Codex could not read the local audio at `#{missing}`: "
             )
           end)

    assert %{
             "type" => "input_text",
             "text" =>
               "Codex cannot attach audio at `#{unsupported}`: unsupported audio format; use wav, mp3, m4a, webm, or ogg."
           } in content

    assert_user_inputs(events, thread, turn, input)
  end

  test "explicit skill selection injects its body once for duplicate path selections", context do
    sentinel = "SAMGITA_EXPLICIT_SKILL_BODY_163"
    path = write_skill(context, "fixture-selection", sentinel)
    selection = %{"type" => "skill", "name" => "fixture-selection", "path" => path}
    pid = start(context)
    assert_skill(pid, context, path, true)
    thread = thread(context, pid)

    input = [text("Use the selected synthetic fixture instructions"), selection, selection]
    turn = start_turn(pid, thread, input)
    events = finish_turn(pid, thread, turn)
    body = provider_text(context.fixture)

    assert [_before, _after] = String.split(body, sentinel)
    assert_user_inputs(events, thread, turn, [selection, selection])
  end

  test "disabled and unmatched structured skills block plain-name fallback", context do
    disabled_sentinel = "SAMGITA_DISABLED_SKILL_BODY_163"
    unmatched_sentinel = "SAMGITA_UNMATCHED_SKILL_BODY_163"
    disabled = write_skill(context, "fixture-disabled", disabled_sentinel)
    matched = write_skill(context, "fixture-unmatched", unmatched_sentinel)
    missing = Path.join(context.fixture.codex_home, "skills/missing/SKILL.md")

    File.write!(
      Path.join(context.fixture.codex_home, "config.toml"),
      "\n[[skills.config]]\npath = #{JSON.encode!(disabled)}\nenabled = false\n",
      [:append]
    )

    pid = start(context)
    assert_skill(pid, context, disabled, false)
    assert_skill(pid, context, matched, true)
    thread = thread(context, pid)

    input = [
      text("Use $fixture-disabled and $fixture-unmatched for this synthetic fixture"),
      %{"type" => "skill", "name" => "fixture-disabled", "path" => disabled},
      %{"type" => "skill", "name" => "fixture-unmatched", "path" => missing}
    ]

    turn = start_turn(pid, thread, input)
    events = finish_turn(pid, thread, turn)
    body = provider_text(context.fixture)
    refute String.contains?(body, disabled_sentinel)
    refute String.contains?(body, unmatched_sentinel)
    assert_user_inputs(events, thread, turn, tl(input))
  end

  test "unknown app and plugin mentions retain structured identity in user item events",
       context do
    pid = start(context)
    thread = thread(context, pid)

    mentions = [
      %{"type" => "mention", "name" => "Synthetic App", "path" => "app://samgita-unknown"},
      %{
        "type" => "mention",
        "name" => "Synthetic Plugin",
        "path" => "plugin://samgita-unknown@synthetic"
      }
    ]

    turn =
      start_turn(pid, thread, [text("Preserve synthetic mention identities only") | mentions])

    events = finish_turn(pid, thread, turn)
    assert_user_inputs(events, thread, turn, mentions)

    # Unknown mentions add no model content; this does not qualify real routing or permissions.
    body = provider_text(context.fixture)
    refute String.contains?(body, "app://samgita-unknown")
    refute String.contains?(body, "plugin://samgita-unknown@synthetic")
  end

  defp text(value), do: %{"type" => "text", "text" => value}

  defp audio_urls(content) do
    for %{"type" => "input_audio", "audio_url" => url} <- content, do: url
  end

  defp provider_text(fixture) do
    fixture |> provider_content() |> Enum.map_join("\n", &(&1["text"] || ""))
  end

  defp write_skill(context, name, sentinel) do
    path = Path.join([context.fixture.codex_home, "skills", name, "SKILL.md"])
    File.mkdir_p!(Path.dirname(path))

    File.write!(
      path,
      "---\nname: #{name}\ndescription: Synthetic attachment qualification skill\n---\n\n#{sentinel}\n"
    )

    path
  end

  defp assert_skill(pid, context, path, enabled) do
    result = call(pid, "skills/list", %{"cwds" => [context.fixture.workspace]})
    skills = Enum.flat_map(result["data"], & &1["skills"])
    assert Enum.any?(skills, &(&1["path"] == path and &1["enabled"] == enabled))
  end

  defp assert_user_inputs(events, thread, turn, inputs) do
    for method <- ["item/started", "item/completed"] do
      params =
        notification(events, method, fn params ->
          params["threadId"] == thread and params["turnId"] == turn and
            get_in(params, ["item", "type"]) == "userMessage"
        end)

      actual = get_in(params, ["item", "content"])

      for input <- inputs, do: assert(input in actual)

      for input <- Enum.uniq(inputs) do
        assert Enum.count(actual, &(&1 == input)) == Enum.count(inputs, &(&1 == input))
      end
    end
  end
end
