defmodule SamgitaCodexDriver.ToolOutputTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @max_chars 1_048_576

  setup {TurnFixture, :setup}

  for experimental <- [false, true] do
    @tag experimental: experimental
    test "standalone tool outputs persist across process restart, experimental=#{experimental}",
         context do
      pid = start(context, experimental: context.experimental)

      outputs = [
        %{"name" => "missing_options", "output" => "Synthetic standalone result"},
        %{
          "name" => "structured_text",
          "namespace" => nil,
          "output" => [
            %{"type" => "input_text", "text" => "First synthetic fragment"},
            %{"type" => "input_text", "text" => "Second fragment: é🙂"}
          ],
          "retain" => false
        },
        %{
          "name" => "retained_text",
          "namespace" => "synthetic_namespace",
          "output" => "Synthetic retained annotation: é🙂",
          "retain" => true
        },
        %{"name" => "empty_text", "output" => "", "retain" => true},
        %{"name" => "empty_array", "namespace" => "", "output" => [], "retain" => false}
      ]

      recorded =
        Enum.map(outputs, fn output ->
          thread = thread(context, pid)
          turn = start_turn(pid, thread, [], %{"toolOutput" => output})
          events = finish_turn(pid, thread, turn)

          expected = %{
            "type" => "functionCallOutput",
            "name" => output["name"],
            "namespace" => output["namespace"],
            "output" => output["output"]
          }

          completed =
            notification(events, "item/completed", &(&1["item"]["type"] == "functionCallOutput"))

          assert %{"threadId" => ^thread, "turnId" => ^turn, "item" => %{"id" => item_id}} =
                   completed

          assert is_binary(item_id) and byte_size(item_id) > 0
          expected = Map.put(expected, "id", item_id)
          assert completed["item"] == expected

          assert %{"threadId" => ^thread, "turnId" => ^turn, "item" => ^expected} =
                   notification(events, "item/started", &(&1["item"]["id"] == item_id))

          refute notification(events, "item/started", &(&1["item"]["type"] == "userMessage"))

          read = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})
          assert_persisted_output(read, thread, turn, expected)
          {thread, turn, expected, read["thread"]["path"], Map.get(output, "retain", false)}
        end)

      requests = ModelFixture.requests(context.fixture)
      assert Enum.count(requests) == Enum.count(outputs)

      item_ids =
        Map.new(recorded, fn {_thread, _turn, item, _path, _retained} ->
          {item["name"], item["id"]}
        end)

      for output <- outputs do
        assert [captured] =
                 requests
                 |> Enum.flat_map(& &1["input"])
                 |> Enum.filter(
                   &(&1["type"] == "function_call_output" and &1["name"] == output["name"])
                 )

        assert captured["output"] == output["output"]
        assert captured["id"] == item_ids[output["name"]]
        assert captured["namespace"] == output["namespace"]
        refute Map.has_key?(captured, "call_id")
        refute Map.has_key?(captured, "retain")
        refute Map.has_key?(captured, "client_authored")

        if is_nil(output["namespace"]), do: refute(Map.has_key?(captured, "namespace"))
      end

      # A confirmed close flushes the owned process before inspecting synthetic rollout files.
      assert :ok = Session.close(pid)

      for {_thread, _turn, item, path, retained} <- recorded do
        assert String.starts_with?(Path.expand(path), context.fixture.codex_home <> "/")

        assert [line] =
                 path
                 |> File.read!()
                 |> String.split("\n", trim: true)
                 |> Enum.map(&JSON.decode!/1)
                 |> Enum.filter(fn line ->
                   line["type"] == "response_item" and
                     get_in(line, ["payload", "id"]) == item["id"]
                 end)

        assert line["payload"]["type"] == "function_call_output"
        assert line["payload"]["output"] == item["output"]

        if retained do
          assert get_in(line, ["metadata", "client_authored"]) == true
        else
          refute get_in(line, ["metadata", "client_authored"])
        end

        refute Map.has_key?(line["payload"], "retain")
      end

      resumed = start(context, experimental: context.experimental)

      for {thread, turn, expected, _path, _retained} <- recorded do
        result = call(resumed, "thread/resume", %{"threadId" => thread})
        assert result["thread"]["id"] == thread
        read = call(resumed, "thread/read", %{"threadId" => thread, "includeTurns" => true})
        assert_persisted_output(read, thread, turn, expected)
      end

      assert ModelFixture.requests(context.fixture) == requests
    end

    @tag experimental: experimental
    test "null or omitted tool output with empty input runs ordinary inference, experimental=#{experimental}",
         context do
      pid = start(context, experimental: context.experimental)

      for extra <- [%{}, %{"toolOutput" => nil}] do
        thread = thread(context, pid)
        turn = start_turn(pid, thread, [], extra)
        events = finish_turn(pid, thread, turn)
        refute notification(events, "item/started", &(&1["item"]["type"] == "functionCallOutput"))
        refute notification(events, "item/started", &(&1["item"]["type"] == "userMessage"))
      end

      assert [first, second] = ModelFixture.requests(context.fixture)

      for request <- [first, second] do
        refute Enum.any?(request["input"], &(&1["type"] == "function_call_output"))
      end
    end

    @tag experimental: experimental
    test "invalid tool output is rejected before inference, experimental=#{experimental}",
         context do
      pid = start(context, experimental: context.experimental)
      thread = thread(context, pid)
      valid = %{"name" => "synthetic_tool", "output" => "Synthetic output"}

      invalid = [
        Map.delete(valid, "name"),
        Map.put(valid, "name", nil),
        Map.delete(valid, "output"),
        Map.put(valid, "output", nil),
        Map.put(valid, "output", %{"text" => "Wrong container"}),
        Map.put(valid, "namespace", 42),
        Map.put(valid, "retain", nil),
        Map.put(valid, "output", [%{"type" => "input_text", "text" => nil}]),
        Map.put(valid, "output", [%{"type" => "unsupported_content", "text" => "Synthetic"}])
      ]

      base = %{"threadId" => thread, "input" => [], "toolOutput" => valid}

      params =
        Enum.map(invalid, &Map.put(base, "toolOutput", &1)) ++
          [Map.delete(base, "input"), Map.put(base, "input", nil)]

      for params <- params do
        error = upstream_error(pid, "turn/start", params, validation: :wire)
        assert error["code"] == -32_600
        assert error["message"] =~ "Invalid request"
      end

      for {params, message} <- [
            {Map.put(base, "input", [%{"type" => "text", "text" => "Synthetic conflict"}]),
             "`toolOutput` cannot be combined with nonempty `input`"},
            {Map.put(base, "toolOutput", Map.put(valid, "name", "")),
             "`toolOutput.name` must not be empty"}
          ] do
        assert upstream_error(pid, "turn/start", params) == %{
                 "code" => -32_600,
                 "message" => message
               }
      end

      assert_rejected_without_turn(pid, context.fixture)
    end

    @tag experimental: experimental
    test "oversized tool text returns structured native size errors, experimental=#{experimental}",
         context do
      pid = start(context, experimental: context.experimental)
      thread = thread(context, pid)
      first = String.duplicate("é", div(@max_chars, 2))
      second = String.duplicate("x", div(@max_chars, 2) + 1)

      for output <- [
            first <> second,
            [
              %{"type" => "input_text", "text" => first},
              %{"type" => "input_text", "text" => second}
            ]
          ] do
        error =
          upstream_error(pid, "turn/start", %{
            "threadId" => thread,
            "input" => [],
            "toolOutput" => %{"name" => "synthetic_tool", "output" => output}
          })

        assert error == %{
                 "code" => -32_602,
                 "message" => "Input exceeds the maximum length of #{@max_chars} characters.",
                 "data" => %{
                   "input_error_code" => "input_too_large",
                   "max_chars" => @max_chars,
                   "actual_chars" => @max_chars + 1
                 }
               }
      end

      assert_rejected_without_turn(pid, context.fixture)
    end

    @tag experimental: experimental
    test "remote images in structured tool output fail before inference, experimental=#{experimental}",
         context do
      pid = start(context, experimental: context.experimental)
      thread = thread(context, pid)

      for scheme <- ["http", "https", "HTTP", "hTtPs"] do
        error =
          upstream_error(pid, "turn/start", %{
            "threadId" => thread,
            "input" => [],
            "toolOutput" => %{
              "name" => "synthetic_tool",
              "output" => [
                %{
                  "type" => "input_image",
                  "image_url" => scheme <> "://fixture.invalid/pixel.png"
                }
              ]
            }
          })

        assert error == %{
                 "code" => -32_600,
                 "message" =>
                   "remote image URLs are not supported; use an inline data URL instead"
               }
      end

      assert_rejected_without_turn(pid, context.fixture)
    end
  end

  defp assert_persisted_output(read, thread, turn, expected) do
    assert %{"thread" => %{"id" => ^thread, "turns" => [%{"id" => ^turn, "items" => items}]}} =
             read

    assert [^expected] = Enum.filter(items, &(&1["type"] == "functionCallOutput"))
    refute Enum.any?(items, &(&1["type"] == "userMessage"))
  end

  defp assert_rejected_without_turn(pid, fixture) do
    assert [] = ModelFixture.requests(fixture)
    assert {:ok, events} = Session.drain(pid)
    refute notification(events, "turn/started")
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
  end
end
