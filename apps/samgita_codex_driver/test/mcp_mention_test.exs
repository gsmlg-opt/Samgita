defmodule SamgitaCodexDriver.McpMentionTest do
  use ExUnit.Case, async: false

  import SamgitaCodexDriver.TurnFixture

  alias SamgitaCodexDriver.{ModelFixture, Session}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/server_interaction_fixture.py", __DIR__)

  test "exact MCP mention waits for optional startup and exposes its direct tool independent of display name" do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-codex-mention-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    for mentioned <- [false, true] do
      fixture = fixture(Path.join(root, to_string(mentioned)))
      release = Path.join(fixture.codex_home, "startup-release")

      try do
        context = %{binary: binary, fixture: fixture}
        configure_model(context, %{"supports_search_tool" => false})
        pid = start(context)

        try do
          thread = thread(context, pid)
          wait_for_file(Path.join(fixture.codex_home, "startup-seen"), now() + 5_000)
          refute File.exists?(release)

          mention = %{
            "type" => "mention",
            "name" => "Unrelated display label",
            "path" => "mcp://fixture"
          }

          input = [%{"type" => "text", "text" => "Complete the synthetic interaction"}]
          input = if mentioned, do: input ++ [mention], else: input
          turn = start_turn(pid, thread, input)

          events =
            if mentioned do
              # Hold initialization beyond the identical optional-server grace in both profiles.
              pending = hold_before_model(pid, fixture, turn, [], now() + 250)
              assert notification(pending, "turn/started", &(&1["turn"]["id"] == turn))
              File.write!(release, "release\n")
              finish(pid, thread, turn, pending, now() + 5_000)
            else
              finish(pid, thread, turn, [], now() + 5_000)
            end

          assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
                   notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

          assert notification(events, "mcpServer/startupStatus/updated", fn params ->
                   params["name"] == "fixture" and params["status"] == "starting"
                 end)

          requests = ModelFixture.requests(fixture)
          [first | _] = requests

          namespace =
            Enum.find(
              first["tools"],
              &(&1["type"] == "namespace" and &1["name"] == "mcp__fixture")
            )

          calls = Enum.filter(events, &(&1.kind == :server_request))

          if mentioned do
            assert namespace
            assert Enum.any?(namespace["tools"], &(&1["name"] == "confirm"))
            assert length(calls) == 1
            assert length(requests) == 2

            for method <- ["item/started", "item/completed"] do
              params =
                notification(events, method, fn params ->
                  params["threadId"] == thread and params["turnId"] == turn and
                    params["item"]["type"] == "userMessage"
                end)

              assert mention in params["item"]["content"]

              params =
                notification(events, method, fn params ->
                  params["threadId"] == thread and params["turnId"] == turn and
                    params["item"]["type"] == "mcpToolCall"
                end)

              assert %{"server" => "fixture", "tool" => "confirm", "arguments" => %{}} =
                       params["item"]

              assert params["item"]["status"] ==
                       if(method == "item/started", do: "inProgress", else: "completed")
            end

            assert notification(events, "mcpServer/startupStatus/updated", fn params ->
                     params["name"] == "fixture" and params["status"] == "ready"
                   end)

            [tool_call] =
              fixture.codex_home
              |> Path.join("mcp-calls.jsonl")
              |> File.read!()
              |> String.split("\n", trim: true)
              |> Enum.map(&JSON.decode!/1)

            assert %{"name" => "confirm", "arguments" => %{}} = tool_call
            reply = fixture.codex_home |> Path.join("mcp.json") |> File.read!() |> JSON.decode!()
            assert reply["result"] == %{"action" => "accept", "content" => %{"confirmed" => true}}

            output =
              Enum.find(
                List.last(requests)["input"],
                &(&1["type"] == "function_call_output" and &1["call_id"] == "interaction-call-1")
              )

            assert output

            assert [
                     %{"type" => "input_text", "text" => header},
                     %{"type" => "input_text", "text" => accepted}
                   ] = output["output"]

            assert header =~ ~r/^Wall time: \d+\.\d{4} seconds\nOutput:$/
            assert JSON.decode!(accepted) == reply["result"]
          else
            refute namespace
            assert length(requests) == 1
            assert calls == []
            refute File.exists?(Path.join(fixture.codex_home, "mcp-calls.jsonl"))

            refute Enum.any?(
                     events,
                     &(get_in(&1, [:wire, "params", "item", "type"]) == "mcpToolCall")
                   )

            refute notification(
                     events,
                     "mcpServer/startupStatus/updated",
                     &(&1["status"] in ["ready", "failed"])
                   )

            refute File.exists?(release)
          end
        after
          File.write!(release, "release\n")
          if Process.alive?(pid), do: assert(:ok = Session.close(pid))
        end
      after
        File.write!(release, "release\n")
        assert :ok = ModelFixture.close(fixture)
      end
    end
  end

  defp fixture(root) do
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    try do
      fixture = ModelFixture.start(root, "mcp_mention")
      File.write!(fixture.requests, "[]")
      fixture
    after
      if previous,
        do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
        else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
    end
  end

  defp hold_before_model(pid, fixture, turn, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert ModelFixture.requests(fixture) == []
    refute notification(events, "turn/completed", &(&1["turn"]["id"] == turn))
    refute Enum.any?(events, &(&1.kind == :server_request))
    assert Session.status(pid).phase == :ready

    if now() >= deadline do
      events
    else
      pause(pid)
      hold_before_model(pid, fixture, turn, events, deadline)
    end
  end

  defp finish(pid, thread, turn, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)

    for event <- incoming, event.kind == :server_request do
      assert event.wire["method"] == "mcpServer/elicitation/request"

      assert %{"threadId" => ^thread, "serverName" => "fixture", "mode" => "form"} =
               event.wire["params"]

      assert :ok =
               Session.respond(
                 pid,
                 event.handle,
                 {:ok, %{"action" => "accept", "content" => %{"confirmed" => true}}}
               )
    end

    events = events ++ incoming

    cond do
      notification(events, "turn/completed", &(&1["turn"]["id"] == turn)) ->
        events

      now() >= deadline ->
        flunk("MCP mention deadline: #{inspect(Session.status(pid))}")

      true ->
        assert Session.status(pid).phase == :ready
        pause(pid)
        finish(pid, thread, turn, events, deadline)
    end
  end

  defp wait_for_file(path, deadline) do
    cond do
      File.exists?(path) ->
        :ok

      now() >= deadline ->
        flunk("MCP startup marker deadline")

      true ->
        receive do
        after
          10 -> :ok
        end

        wait_for_file(path, deadline)
    end
  end

  defp pause(pid) do
    receive do
      {:codex_driver, ^pid, :events_available} -> :ok
      {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected MCP mention event gap")
    after
      10 -> :ok
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
