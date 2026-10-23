defmodule SamgitaCodexDriver.ImagePreparationTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ImageFixture, ModelFixture, Session, TurnFixture}
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @sources [:inline, :local, :tool_output]
  @processing_error "image content omitted because it could not be processed"
  @low_error "image content omitted because detail 'low' is not supported; use 'high', 'original', or 'auto'"
  @max_chars 1_048_576

  setup {TurnFixture, :setup}

  test "PNG checker rejects corrupt CRCs, truncated streams and valid-CRC wrong pixels" do
    png = ImageFixture.png(2, 2)
    assert {^png, {2, 2}} = png |> ImageFixture.data_url() |> ImageFixture.decode_png!()

    <<prefix::binary-size(33), size::32, "IDAT", data::binary-size(size), crc::32,
      ending::binary>> = png

    corrupt_crc =
      prefix <> <<size::32, "IDAT", data::binary, Bitwise.bxor(crc, 1)::32>> <> ending

    wrong_data = :zlib.compress(:binary.copy(<<0>>, 14))
    wrong_crc = :erlang.crc32("IDAT" <> wrong_data)

    wrong_pixels =
      prefix <>
        <<byte_size(wrong_data)::32, "IDAT", wrong_data::binary, wrong_crc::32>> <> ending

    bad_iend = binary_part(png, 0, byte_size(png) - 1) <> <<1>>
    truncated = binary_part(png, 0, byte_size(png) - 1)

    for invalid <- [corrupt_crc, bad_iend, truncated, wrong_pixels, png <> <<0>>, png <> ending] do
      assert_raise ExUnit.AssertionError, fn ->
        invalid |> ImageFixture.data_url() |> ImageFixture.decode_png!()
      end
    end
  end

  test "small PNG bytes survive inline, local and structured output preparation", context do
    configure_model(context, %{})
    pid = start(context)
    bytes = ImageFixture.png(64, 32)

    for source <- @sources do
      [image] = context |> image(pid, source, bytes, "high") |> images()
      assert image["detail"] == "high"
      assert {^bytes, {64, 32}} = ImageFixture.decode_png!(image["image_url"])
    end
  end

  test "high preparation enforces the patch budget on all three input paths", context do
    configure_model(context, %{})
    pid = start(context)
    bytes = ImageFixture.png(2048, 2048)

    # The dimension limit alone would leave this image unchanged (64*64 > 2500 patches).
    for source <- @sources do
      [image] = context |> image(pid, source, bytes, "high") |> images()
      assert image["detail"] == "high"
      assert {prepared, {1600, 1600}} = ImageFixture.decode_png!(image["image_url"])
      refute prepared == bytes
    end
  end

  test "original preparation uses its larger dimension and patch budgets", context do
    configure_model(context, %{"supports_image_detail_original" => true})
    pid = start(context)

    for {width, height, dimensions} <- [
          {2048, 2048, {2048, 2048}},
          {3201, 3201, {3200, 3200}},
          {6401, 100, {6000, 94}}
        ] do
      bytes = ImageFixture.png(width, height)

      for source <- @sources do
        [image] = context |> image(pid, source, bytes, "original") |> images()
        assert image["detail"] == "original"
        assert {prepared, ^dimensions} = ImageFixture.decode_png!(image["image_url"])

        if dimensions == {width, height},
          do: assert(prepared == bytes),
          else: refute(prepared == bytes)
      end
    end
  end

  test "unsupported original detail normalizes after preparation on each path", context do
    configure_model(context, %{"supports_image_detail_original" => false})
    pid = start(context)
    bytes = ImageFixture.png(2048, 2048)

    for source <- @sources do
      [image] = context |> image(pid, source, bytes, "original") |> images()
      assert image["detail"] == "high"
      # Receiving-model normalization changes the detail, not the original-budget pixels.
      assert {^bytes, {2048, 2048}} = ImageFixture.decode_png!(image["image_url"])
    end
  end

  test "omitted and null structured detail use high pixels without adding a wire detail",
       context do
    configure_model(context, %{})
    pid = start(context)
    bytes = ImageFixture.png(2048, 2048)

    for detail <- [:omitted, nil] do
      [image] = context |> image(pid, :tool_output, bytes, detail) |> images()
      refute Map.has_key?(image, "detail")
      assert {_, {1600, 1600}} = ImageFixture.decode_png!(image["image_url"])
    end
  end

  test "data URI case and declared MIME normalize from actual image bytes", context do
    configure_model(context, %{})
    pid = start(context)
    bytes = ImageFixture.png(64, 32)
    uri = "DATA:application/octet-stream;BASE64," <> Base.encode64(bytes)

    for source <- [:inline, :tool_output] do
      original = [image_content(source, uri, "high")]
      [image] = context |> submit(pid, source, original) |> images()
      assert image["image_url"] == ImageFixture.data_url(bytes)
      assert {^bytes, {64, 32}} = ImageFixture.decode_png!(image["image_url"])
    end
  end

  test "only failed data images become ordered placeholders in user and structured output",
       context do
    configure_model(context, %{})
    pid = start(context)
    bytes = ImageFixture.png(64, 32)
    valid = ImageFixture.data_url(bytes)

    for source <- [:inline, :tool_output] do
      original =
        [text_content(source, "before synthetic images")] ++
          Enum.map(
            [
              {"data:image/png;base64", "high"},
              {"data:image/png,AAAA", "high"},
              {"data:image/png;base64,%%%", "high"},
              {ImageFixture.data_url("not an image"), "high"},
              {valid, "low"},
              {valid, "high"}
            ],
            fn {uri, detail} -> image_content(source, uri, detail) end
          ) ++ [text_content(source, "after synthetic images")]

      content = submit(context, pid, source, original)

      assert Enum.map(content, & &1["type"]) ==
               List.duplicate("input_text", 6) ++ ["input_image", "input_text"]

      assert Enum.map(Enum.filter(content, &(&1["type"] == "input_text")), & &1["text"]) ==
               ["before synthetic images"] ++
                 List.duplicate(@processing_error, 4) ++
                 [@low_error, "after synthetic images"]

      [image] = images(content)
      assert {^bytes, {64, 32}} = ImageFixture.decode_png!(image["image_url"])
    end
  end

  test "exact Unicode scalar limit is accepted and one extra scalar fails before inference",
       context do
    configure_model(context, %{
      "context_window" => 8_000_000,
      "truncation_policy" => %{"mode" => "bytes", "limit" => 2_000_000}
    })

    pid = start(context)
    text = String.duplicate("e\u0301", div(@max_chars, 2))
    assert String.length(text) == div(@max_chars, 2)
    assert length(String.to_charlist(text)) == @max_chars
    assert byte_size(text) > @max_chars

    for source <- [:inline, :tool_output] do
      assert [%{"type" => "input_text", "text" => ^text}] =
               submit(context, pid, source, [text_content(source, text)])

      thread = thread(context, pid)
      params = %{"threadId" => thread, "input" => []}

      params =
        if source == :tool_output,
          do:
            Map.put(params, "toolOutput", %{"name" => "synthetic_image", "output" => text <> "x"}),
          else: Map.put(params, "input", [%{"type" => "text", "text" => text <> "x"}])

      previous = ModelFixture.requests(context.fixture)

      assert upstream_error(pid, "turn/start", params) == %{
               "code" => -32_602,
               "message" => "Input exceeds the maximum length of #{@max_chars} characters.",
               "data" => %{
                 "input_error_code" => "input_too_large",
                 "max_chars" => @max_chars,
                 "actual_chars" => @max_chars + 1
               }
             }

      assert ModelFixture.requests(context.fixture) == previous
      assert {:ok, events} = Session.drain(pid)
      refute notification(events, "turn/started")
      assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
    end
  end

  defp image(context, pid, source, bytes, detail) do
    uri = ImageFixture.data_url(bytes)

    input =
      if source == :local do
        path =
          Path.join(context.fixture.workspace, "image-#{System.unique_integer([:positive])}.png")

        File.write!(path, bytes)
        with_detail(%{"type" => "localImage", "path" => path}, detail)
      else
        image_content(source, uri, detail)
      end

    submit(context, pid, source, [input])
  end

  defp submit(context, pid, source, original) do
    previous = ModelFixture.requests(context.fixture)
    thread = thread(context, pid)

    turn =
      if source == :tool_output do
        start_turn(pid, thread, [], %{
          "toolOutput" => %{"name" => "synthetic_image", "output" => original}
        })
      else
        start_turn(pid, thread, original)
      end

    events = finish_turn(pid, thread, turn)
    type = if source == :tool_output, do: "functionCallOutput", else: "userMessage"
    key = if source == :tool_output, do: "output", else: "content"
    expected = Enum.map(original, &native_content(&1, source))

    items =
      for method <- ["item/started", "item/completed"] do
        assert %{"threadId" => ^thread, "turnId" => ^turn, "item" => item} =
                 notification(events, method, &(&1["item"]["type"] == type))

        assert item[key] == expected
        item
      end

    assert Enum.map(items, & &1["id"]) |> Enum.uniq() |> length() == 1
    requests = ModelFixture.requests(context.fixture)
    assert {^previous, [request]} = Enum.split(requests, length(previous))

    if source == :tool_output do
      [output] =
        Enum.filter(
          request["input"],
          &(&1["type"] == "function_call_output" and &1["name"] == "synthetic_image")
        )

      output["output"]
    else
      request["input"]
      |> Enum.filter(&(&1["role"] == "user"))
      |> List.last()
      |> Map.fetch!("content")
    end
  end

  defp native_content(content, :tool_output) do
    if Map.has_key?(content, "detail") and is_nil(content["detail"]),
      do: Map.delete(content, "detail"),
      else: content
  end

  defp native_content(%{"type" => "text"} = content, _source),
    do: Map.put_new(content, "text_elements", [])

  defp native_content(content, _source), do: Map.put_new(content, "detail", nil)

  defp image_content(:tool_output, uri, detail),
    do: with_detail(%{"type" => "input_image", "image_url" => uri}, detail)

  defp image_content(_source, uri, detail),
    do: with_detail(%{"type" => "image", "url" => uri}, detail)

  defp text_content(:tool_output, text), do: %{"type" => "input_text", "text" => text}
  defp text_content(_source, text), do: %{"type" => "text", "text" => text}
  defp with_detail(content, :omitted), do: content
  defp with_detail(content, detail), do: Map.put(content, "detail", detail)
  defp images(content), do: Enum.filter(content, &(&1["type"] == "input_image"))
end
