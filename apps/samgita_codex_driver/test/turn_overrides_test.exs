defmodule SamgitaCodexDriver.TurnOverridesTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000

  setup {TurnFixture, :setup}

  test "model effort and summary overrides persist and public null preserves them", context do
    pid = start(context)
    thread = thread(context, pid)

    for extra <- [
          %{"model" => "mock-model-override", "effort" => "high", "summary" => "detailed"},
          %{},
          %{"model" => nil, "effort" => nil, "summary" => nil},
          %{"model" => "mock-model", "effort" => "low", "summary" => "none"},
          %{}
        ] do
      finish_turn(pid, thread, start_turn(pid, thread, text(), extra))
    end

    [first, inherited, null_inherited, changed, inherited_changed] =
      ModelFixture.requests(context.fixture)

    for request <- [first, inherited, null_inherited] do
      assert request["model"] == "mock-model-override"
      assert request["reasoning"] == %{"effort" => "high", "summary" => "detailed"}
    end

    for request <- [changed, inherited_changed] do
      assert request["model"] == "mock-model"
      assert request["reasoning"] == %{"effort" => "low"}
    end
  end

  test "collaboration mode overrides conflicting model and effort and supplies its preset",
       context do
    pid = start(context)

    for instructions <- [nil, "Synthetic explicit collaboration instructions", ""] do
      thread = thread(context, pid)

      mode = %{
        "mode" => "default",
        "settings" => %{
          "model" => "mock-model-collab",
          "reasoning_effort" => "high",
          "developer_instructions" => instructions
        }
      }

      turn =
        start_turn(pid, thread, text(), %{
          "model" => "mock-model-conflict",
          "effort" => "low",
          "collaborationMode" => mode
        })

      events = finish_turn(pid, thread, turn)

      assert %{
               "threadId" => ^thread,
               "threadSettings" => %{
                 "model" => "mock-model-collab",
                 "effort" => "high",
                 "collaborationMode" => %{"settings" => settings}
               }
             } = notification(events, "thread/settings/updated")

      assert settings["model"] == "mock-model-collab"

      case instructions do
        nil -> assert settings["developer_instructions"] =~ "Use the `request_user_input` tool"
        value -> assert settings["developer_instructions"] == value
      end
    end

    [preset, explicit, empty] = ModelFixture.requests(context.fixture)

    for request <- [preset, explicit, empty] do
      assert request["model"] == "mock-model-collab"
      assert request["reasoning"]["effort"] == "high"
    end

    assert developer_text(preset) =~ "Use the `request_user_input` tool"
    assert developer_text(explicit) =~ "Synthetic explicit collaboration instructions"
    refute developer_text(explicit) =~ "Use the `request_user_input` tool"
    refute developer_text(empty) =~ "Synthetic explicit collaboration instructions"
    refute developer_text(empty) =~ "Use the `request_user_input` tool"
  end

  test "experimental environment overrides reject disabled negotiation before a turn", context do
    pid = start(context, experimental: false)
    thread = thread(context, pid)

    for {field, value} <- [
          {"environments", []},
          {"runtimeWorkspaceRoots", [context.fixture.workspace]},
          {"permissions", ":read-only"}
        ] do
      error =
        upstream_error(
          pid,
          "turn/start",
          %{"threadId" => thread, "input" => text(), field => value},
          validation: :wire
        )

      assert error == %{
               "code" => -32_600,
               "message" => "turn/start.#{field} requires experimentalApi capability"
             }
    end

    assert [] = ModelFixture.requests(context.fixture)
    assert {:ok, events} = Session.drain(pid)
    refute notification(events, "turn/started")
  end

  test "unknown environments and conflicting permissions reject without model execution",
       context do
    pid = start(context)
    thread = thread(context, pid)

    error =
      upstream_error(pid, "turn/start", %{
        "threadId" => thread,
        "input" => text(),
        "environments" => [
          %{"environmentId" => "synthetic-missing", "cwd" => context.fixture.workspace}
        ]
      })

    assert error == %{
             "code" => -32_600,
             "message" => "unknown turn environment id `synthetic-missing`"
           }

    error =
      upstream_error(pid, "turn/start", %{
        "threadId" => thread,
        "input" => text(),
        "permissions" => ":read-only",
        "sandboxPolicy" => %{"type" => "readOnly"}
      })

    assert error == %{
             "code" => -32_600,
             "message" => "`permissions` cannot be combined with `sandboxPolicy`"
           }

    assert [] = ModelFixture.requests(context.fixture)
    assert {:ok, events} = Session.drain(pid)
    refute notification(events, "turn/started")

    finish_turn(pid, thread, start_turn(pid, thread, text()))
    assert [_request] = ModelFixture.requests(context.fixture)
  end

  defp text, do: [%{"type" => "text", "text" => "Synthetic turn setting probe"}]

  defp developer_text(request) do
    request["input"]
    |> Enum.filter(&(&1["role"] == "developer"))
    |> Enum.flat_map(&Map.get(&1, "content", []))
    |> Enum.map_join("\n", &Map.get(&1, "text", ""))
  end
end
