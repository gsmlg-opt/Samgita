defmodule SamgitaCodexDriver.TurnInputTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  import SamgitaCodexDriver.TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @pixel "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC"
  @details [
    {:omitted, "high"},
    {nil, "high"},
    {"auto", "auto"},
    {"low", :omitted},
    {"high", "high"},
    {"original", "high"}
  ]

  setup {TurnFixture, :setup}

  for experimental <- [false, true] do
    @tag experimental: experimental
    test "UTF-8 spans and client IDs persist through restart, experimental=#{experimental}",
         context do
      pid = start(context, experimental: context.experimental)
      id = thread(context, pid)
      client = "fixture-client-utf8-#{context.experimental}"

      elements = [
        %{"byteRange" => %{"start" => 0, "end" => 2}, "placeholder" => "accent"},
        %{"byteRange" => %{"start" => 2, "end" => 6}},
        %{"byteRange" => %{"start" => 6, "end" => 7}, "placeholder" => nil}
      ]

      input = %{"type" => "text", "text" => "é🙂x", "text_elements" => elements}

      expected = %{
        input
        | "text_elements" => Enum.map(elements, &Map.put_new(&1, "placeholder", nil))
      }

      turn = start_turn(pid, id, [input], %{"clientUserMessageId" => client})
      events = finish_turn(pid, id, turn)

      for method <- ["item/started", "item/completed"] do
        assert %{
                 "threadId" => ^id,
                 "turnId" => ^turn,
                 "item" => %{"clientId" => ^client, "content" => [^expected]}
               } =
                 notification(events, method, &(&1["item"]["type"] == "userMessage"))
      end

      assert %{"type" => "input_text", "text" => "é🙂x"} in provider_content(context.fixture)
      [request] = ModelFixture.requests(context.fixture)
      refute JSON.encode!(request) =~ "text_elements"
      assert :ok = Session.close(pid)

      resumed = start(context, experimental: context.experimental)
      result = call(resumed, "thread/resume", %{"threadId" => id})
      assert result["thread"]["id"] == id
      read = call(resumed, "thread/read", %{"threadId" => id, "includeTurns" => true})
      assert [%{"id" => ^turn, "items" => items}] = read["thread"]["turns"]

      assert %{"clientId" => ^client, "content" => [^expected]} =
               Enum.find(items, &(&1["type"] == "userMessage"))

      assert [^request] = ModelFixture.requests(context.fixture)
    end
  end

  test "omitted text spans normalize to an empty array without changing text", context do
    pid = start(context)
    id = thread(context, pid)

    input = [
      %{"type" => "text", "text" => "first"},
      %{"type" => "text", "text" => "second", "text_elements" => []}
    ]

    turn = start_turn(pid, id, input)
    events = finish_turn(pid, id, turn)
    expected = Enum.map(input, &Map.put_new(&1, "text_elements", []))

    assert_user_content(events, id, turn, expected)

    assert notification(events, "item/started", &(&1["item"]["type"] == "userMessage"))["item"][
             "clientId"
           ] == nil

    assert %{"type" => "input_text", "text" => "first"} in provider_content(context.fixture)
    assert %{"type" => "input_text", "text" => "second"} in provider_content(context.fixture)
  end

  test "malformed span types fail at the actual server before model execution", context do
    pid = start(context)
    id = thread(context, pid)

    for elements <- [
          nil,
          [%{"byteRange" => %{"start" => -1, "end" => 1}}],
          [%{"byteRange" => %{"start" => "zero", "end" => 1}}],
          [%{"byteRange" => %{"start" => 0, "end" => 1}, "placeholder" => 42}]
        ] do
      error =
        upstream_error(
          pid,
          "turn/start",
          %{
            "threadId" => id,
            "input" => [%{"type" => "text", "text" => "x", "text_elements" => elements}]
          },
          validation: :wire
        )

      assert error["code"] == -32_600
      assert error["message"] =~ "Invalid request"
    end

    assert ModelFixture.requests(context.fixture) == []
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
  end

  test "inline images retain native detail and upstream model normalization", context do
    pid = start(context)

    for {supplied, expected_detail} <- @details do
      id = thread(context, pid)
      image = with_detail(%{"type" => "image", "url" => @pixel}, supplied)
      turn = start_turn(pid, id, [%{"type" => "text", "text" => "Synthetic pixel"}, image])
      events = finish_turn(pid, id, turn)

      if expected_detail == :omitted do
        assert_low_detail_omitted(context)
      else
        assert [%{"image_url" => @pixel, "detail" => ^expected_detail}] = latest_images(context)
      end

      assert_user_content(events, id, turn, [
        %{"type" => "text", "text" => "Synthetic pixel", "text_elements" => []},
        Map.put(image, "detail", detail_value(supplied))
      ])
    end
  end

  test "local images default to high and preserve explicit detail in item evidence", context do
    path = Path.join(context.fixture.workspace, "synthetic pixel.png")
    File.write!(path, png())
    pid = start(context)

    for {supplied, expected_detail} <- @details do
      id = thread(context, pid)
      image = with_detail(%{"type" => "localImage", "path" => path}, supplied)
      turn = start_turn(pid, id, [image])
      events = finish_turn(pid, id, turn)

      if expected_detail == :omitted do
        assert_low_detail_omitted(context)
      else
        assert [%{"image_url" => uri, "detail" => ^expected_detail}] = latest_images(context)
        assert String.starts_with?(uri, "data:image/png;base64,")
      end

      assert_user_content(events, id, turn, [Map.put(image, "detail", detail_value(supplied))])
    end
  end

  test "a model advertising original image detail receives original for local and inline inputs",
       context do
    configure_model(context, %{"supports_image_detail_original" => true})
    path = Path.join(context.fixture.workspace, "original.png")
    File.write!(path, png())
    pid = start(context)
    id = thread(context, pid)

    input = [
      %{"type" => "image", "url" => @pixel, "detail" => "original"},
      %{"type" => "localImage", "path" => path, "detail" => "original"}
    ]

    turn = start_turn(pid, id, input)
    events = finish_turn(pid, id, turn)
    assert [%{"detail" => "original"}, %{"detail" => "original"}] = latest_images(context)
    assert_user_content(events, id, turn, input)
  end

  test "file image references reach the provider without implying upload or resolution",
       context do
    pid = start(context)
    id = thread(context, pid)
    image = %{"type" => "image", "fileId" => "file-synthetic-163", "detail" => "low"}
    turn = start_turn(pid, id, [image])
    events = finish_turn(pid, id, turn)

    assert [%{"file_id" => "file-synthetic-163", "detail" => "low"} = captured] =
             latest_images(context)

    refute Map.has_key?(captured, "image_url")
    assert_user_content(events, id, turn, [image])
  end

  test "HTTP image references fail explicitly without a model request", context do
    pid = start(context)
    id = thread(context, pid)

    for scheme <- ["http", "https", "HTTP", "hTtPs"] do
      error =
        upstream_error(pid, "turn/start", %{
          "threadId" => id,
          "input" => [%{"type" => "image", "url" => scheme <> "://fixture.invalid/pixel.png"}]
        })

      assert error == %{
               "code" => -32_600,
               "message" => "remote image URLs are not supported; use an inline data URL instead"
             }
    end

    assert ModelFixture.requests(context.fixture) == []
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
  end

  test "missing and corrupt local images yield upstream error text, preserving original item input",
       context do
    missing = Path.join(context.fixture.workspace, "missing.png")
    corrupt = Path.join(context.fixture.workspace, "corrupt.png")
    File.write!(corrupt, binary_part(png(), 0, 28))
    pid = start(context)
    id = thread(context, pid)

    input = [
      %{"type" => "localImage", "path" => missing},
      %{"type" => "localImage", "path" => corrupt}
    ]

    turn = start_turn(pid, id, input)
    events = finish_turn(pid, id, turn)
    assert latest_images(context) == []
    texts = provider_content(context.fixture) |> Enum.map(&Map.get(&1, "text", ""))

    assert Enum.any?(
             texts,
             &String.starts_with?(&1, "Codex could not read the local image at `#{missing}`:")
           )

    assert "image content omitted because it could not be processed" in texts
    assert_user_content(events, id, turn, Enum.map(input, &Map.put(&1, "detail", nil)))
  end

  defp with_detail(input, :omitted), do: input
  defp with_detail(input, detail), do: Map.put(input, "detail", detail)
  defp detail_value(:omitted), do: nil
  defp detail_value(detail), do: detail
  defp png, do: @pixel |> String.split(",", parts: 2) |> List.last() |> Base.decode64!()

  defp latest_content(context) do
    context.fixture
    |> ModelFixture.requests()
    |> List.last()
    |> Map.fetch!("input")
    |> Enum.flat_map(&Map.get(&1, "content", []))
  end

  defp latest_images(context),
    do: Enum.filter(latest_content(context), &(&1["type"] == "input_image"))

  defp assert_low_detail_omitted(context) do
    assert latest_images(context) == []

    assert %{
             "type" => "input_text",
             "text" =>
               "image content omitted because detail 'low' is not supported; use 'high', 'original', or 'auto'"
           } in latest_content(context)
  end

  defp assert_user_content(events, thread, turn, content) do
    for method <- ["item/started", "item/completed"] do
      assert %{"threadId" => ^thread, "turnId" => ^turn, "item" => %{"content" => ^content}} =
               notification(events, method, &(&1["item"]["type"] == "userMessage"))
    end
  end
end
