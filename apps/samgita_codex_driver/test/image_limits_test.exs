defmodule SamgitaCodexDriver.ImageLimitsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ImageFixture, ModelFixture, Session, TurnFixture}
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @image_byte_limit 1_073_741_824
  @processing_error "image content omitted because it could not be processed"
  @sources [:inline, :local, :tool_output]
  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  setup {TurnFixture, :setup}

  test "queued local images reject oversized sparse files before reading or changing the queue",
       context do
    pid = start(context)
    id = thread(context, pid)
    turn = start_turn(pid, id, [%{"type" => "text", "text" => "Persist synthetic image queue"}])
    finish_turn(pid, id, turn)
    # A cold app-server keeps this durable thread unloaded, so queue edits
    # cannot automatically dispatch its preserved submission.
    assert :ok = Session.close(pid)
    pid = start(context)
    refute id in call(pid, "thread/loaded/list", %{})["data"]

    queued =
      call(pid, "thread/queue/add", %{
        "threadId" => id,
        "clientUserMessageId" => "preserved-image-queue-message",
        "input" => [%{"type" => "text", "text" => "Keep this queued text unchanged"}]
      })["queuedSubmission"]

    # protocol/local_media.rs checks metadata before read_bounded_local_media.
    # ext/queue/service.rs uses that path; direct turn/start does not, so this
    # sparse file must only be submitted through the queue's add/update RPCs.
    path = Path.join(context.fixture.workspace, "oversized-sparse.png")
    create_sparse_file(path, @image_byte_limit + 1)
    assert_sparse_file(path, @image_byte_limit + 1)
    image = [%{"type" => "localImage", "path" => path, "detail" => "high"}]

    for {method, params} <- [
          {"thread/queue/add",
           %{"threadId" => id, "clientUserMessageId" => "rejected-image", "input" => image}},
          {"thread/queue/update",
           %{"threadId" => id, "queuedSubmissionId" => queued["id"], "input" => image}}
        ] do
      assert upstream_error(pid, method, params) == %{
               "code" => -32_600,
               "message" =>
                 "local queued attachment is invalid: image input exceeds #{@image_byte_limit} bytes"
             }

      assert call(pid, "thread/queue/list", %{"threadId" => id})["data"] == [queued]
      assert_sparse_file(path, @image_byte_limit + 1)
      assert length(ModelFixture.requests(context.fixture)) == 1
      assert {:ok, events} = Session.drain(pid)
      refute notification(events, "turn/started")
      assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
    end
  end

  for {detail, patch_boundary, dimension_boundary} <- [
        {"high", 1600, 2048},
        {"original", 3200, 6000}
      ] do
    @tag detail: detail, patch_boundary: patch_boundary, dimension_boundary: dimension_boundary
    test "#{detail} accepts exact patch and dimension boundaries and resizes one pixel over",
         context do
      configure_model(context, %{"supports_image_detail_original" => true})
      pid = start(context)

      for {width, height, expected} <- [
            {context.patch_boundary, context.patch_boundary,
             {context.patch_boundary, context.patch_boundary}},
            {context.patch_boundary + 1, context.patch_boundary + 1,
             {context.patch_boundary, context.patch_boundary}},
            {context.dimension_boundary, 32, {context.dimension_boundary, 32}},
            {context.dimension_boundary + 1, 32, {context.dimension_boundary, 32}}
          ] do
        bytes = ImageFixture.png(width, height)
        assert byte_size(bytes) < 100_000

        for source <- @sources do
          content = submit(context, pid, source, [image(context, source, bytes, context.detail)])
          assert [prepared] = Enum.filter(content, &(&1["type"] == "input_image"))
          assert prepared["detail"] == context.detail
          assert {prepared_bytes, ^expected} = ImageFixture.decode_png!(prepared["image_url"])

          if expected == {width, height},
            do: assert(prepared_bytes == bytes),
            else: refute(prepared_bytes == bytes)
        end
      end
    end
  end

  test "PNG byte truncation and zero dimensions replace only invalid images on every input path",
       context do
    configure_model(context, %{})
    pid = start(context)
    valid = ImageFixture.png(2, 2)

    # All malformed representations are under 100 bytes. Zero dimensions keep
    # a complete known-good IDAT stream and a valid replacement IHDR CRC.
    invalid = [
      <<>>,
      binary_part(valid, 0, 7),
      binary_part(valid, 0, 8),
      binary_part(valid, 0, 32),
      binary_part(valid, 0, 33),
      zero_dimension_png(0, 1),
      zero_dimension_png(1, 0)
    ]

    for source <- @sources do
      original =
        [text(source, "before image byte boundaries")] ++
          Enum.map(invalid ++ [valid], &image(context, source, &1, "high")) ++
          [text(source, "after image byte boundaries")]

      content = submit(context, pid, source, original)
      texts = for %{"type" => "input_text", "text" => text} <- content, do: text
      assert Enum.count(texts, &(&1 == @processing_error)) == length(invalid)
      assert hd(texts) == "before image byte boundaries"
      assert List.last(texts) == "after image byte boundaries"
      assert [prepared] = Enum.filter(content, &(&1["type"] == "input_image"))
      assert {^valid, {2, 2}} = ImageFixture.decode_png!(prepared["image_url"])
    end
  end

  defp create_sparse_file(path, size) do
    {:ok, file} = :file.open(path, [:write, :binary])

    try do
      assert {:ok, ^size} = :file.position(file, {:bof, size})
      assert :ok = :file.truncate(file)
    after
      :file.close(file)
    end
  end

  defp assert_sparse_file(path, size) do
    assert File.stat!(path).size == size
    # GNU stat reports allocated blocks separately from logical file length.
    # Abort before any RPC if this filesystem materializes the sparse extent.
    assert {allocation, 0} = System.cmd("stat", ["--format=%b %B", path])
    [blocks, block_size] = allocation |> String.split() |> Enum.map(&String.to_integer/1)
    assert blocks * block_size < 1_048_576
  end

  defp zero_dimension_png(width, height) do
    <<_original_header::binary-size(33), encoded_pixels::binary>> = ImageFixture.png(1, 1)
    header = <<width::32, height::32, 8, 2, 0, 0, 0>>
    @png_signature <> chunk("IHDR", header) <> encoded_pixels
  end

  defp chunk(kind, bytes),
    do: <<byte_size(bytes)::32, kind::binary, bytes::binary, :erlang.crc32(kind <> bytes)::32>>

  defp image(context, :local, bytes, detail) do
    path =
      Path.join(context.fixture.workspace, "safe-image-#{System.unique_integer([:positive])}.png")

    File.write!(path, bytes)
    %{"type" => "localImage", "path" => path, "detail" => detail}
  end

  defp image(_context, :inline, bytes, detail),
    do: %{"type" => "image", "url" => ImageFixture.data_url(bytes), "detail" => detail}

  defp image(_context, :tool_output, bytes, detail),
    do: %{
      "type" => "input_image",
      "image_url" => ImageFixture.data_url(bytes),
      "detail" => detail
    }

  defp text(:tool_output, text), do: %{"type" => "input_text", "text" => text}
  defp text(_source, text), do: %{"type" => "text", "text" => text}

  defp submit(context, pid, source, original) do
    previous = length(ModelFixture.requests(context.fixture))
    id = thread(context, pid)

    turn =
      if source == :tool_output do
        start_turn(pid, id, [], %{
          "toolOutput" => %{"name" => "synthetic_image_limits", "output" => original}
        })
      else
        start_turn(pid, id, original)
      end

    events = finish_turn(pid, id, turn)
    type = if source == :tool_output, do: "functionCallOutput", else: "userMessage"
    key = if source == :tool_output, do: "output", else: "content"

    expected =
      Enum.map(original, fn
        %{"type" => "text"} = text -> Map.put(text, "text_elements", [])
        image -> image
      end)

    ids =
      for method <- ["item/started", "item/completed"] do
        assert %{"threadId" => ^id, "turnId" => ^turn, "item" => item} =
                 notification(events, method, &(&1["item"]["type"] == type))

        assert item[key] == expected
        item["id"]
      end

    assert length(Enum.uniq(ids)) == 1

    requests = ModelFixture.requests(context.fixture)
    assert length(requests) == previous + 1
    request = List.last(requests)

    if source == :tool_output do
      assert [output] =
               Enum.filter(
                 request["input"],
                 &(&1["type"] == "function_call_output" and &1["name"] == "synthetic_image_limits")
               )

      output["output"]
    else
      request["input"]
      |> Enum.filter(&(&1["role"] == "user"))
      |> List.last()
      |> Map.fetch!("content")
    end
  end
end
