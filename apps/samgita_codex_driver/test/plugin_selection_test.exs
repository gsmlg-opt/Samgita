defmodule SamgitaCodexDriver.PluginSelectionTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @name "fixture-capabilities"
  @marker "SYNTHETIC_EXPLICIT_PLUGIN_SKILL_BODY"
  @hint "Capabilities from the `#{@name}` plugin:"

  setup context do
    context = TurnFixture.setup(context)
    workspace = context.fixture.workspace
    marketplace = Path.join(workspace, ".agents/plugins/marketplace.json")
    plugin = Path.join(workspace, @name)
    skill = Path.join(plugin, "skills/inspect/SKILL.md")
    File.mkdir_p!(Path.join(workspace, ".git"))
    File.mkdir_p!(Path.dirname(marketplace))
    File.mkdir_p!(Path.join(plugin, ".codex-plugin"))
    File.mkdir_p!(Path.dirname(skill))

    File.write!(
      marketplace,
      JSON.encode!(%{
        "name" => "fixture-market",
        "plugins" => [
          %{"name" => @name, "source" => %{"source" => "local", "path" => "./#{@name}"}}
        ]
      })
    )

    File.write!(
      Path.join(plugin, ".codex-plugin/plugin.json"),
      JSON.encode!(%{"name" => @name, "description" => "Synthetic local capabilities"})
    )

    File.write!(
      skill,
      "---\nname: inspect\ndescription: Synthetic explicit inspection\n---\n#{@marker}\n"
    )

    File.write!(
      Path.join(context.fixture.codex_home, "config.toml"),
      "\n[features]\nplugins = true\nremote_plugin = false\n",
      [:append]
    )

    Map.put(context, :marketplace, marketplace)
  end

  test "duplicate structured plugin selections inject one hint with exact identity", context do
    {pid, plugin, _skill} = installed(context)
    thread = thread(context, pid)
    selected = mention(plugin)
    input = [text("Complete this synthetic selection"), selected, selected]
    turn = start_turn(pid, thread, input)
    events = finish_turn(pid, thread, turn)
    assert_user_content(events, thread, turn, input)

    assert [request] = ModelFixture.requests(context.fixture)
    assert count_messages(request, "developer", @hint) == 1
    assert count_messages(request, "developer", "Skills from this plugin") == 1
    assert count_messages(request, "user", @marker) == 0
    refute JSON.encode!(request["input"]) =~ "MCP servers from this plugin"
    refute JSON.encode!(request["input"]) =~ "Apps from this plugin"
  end

  test "plugin links use the at sigil and exact path rather than display name", context do
    {pid, plugin, _skill} = installed(context)

    for {input, expected} <- [
          {[text("Use [@unrelated](plugin://#{plugin}) for the synthetic selection")], 1},
          {[text("Use [$unrelated](plugin://#{plugin}) for the synthetic selection")], 0},
          {[
             text("Complete this synthetic selection"),
             %{"type" => "mention", "name" => @name, "path" => "plugin://unknown@fixture-market"}
           ], 0}
        ] do
      thread = thread(context, pid)
      turn = start_turn(pid, thread, input)
      events = finish_turn(pid, thread, turn)
      assert_user_content(events, thread, turn, input)
      request = List.last(ModelFixture.requests(context.fixture))
      assert count_messages(request, "developer", @hint) == expected
      assert count_messages(request, "user", @marker) == 0
    end

    assert [_, _, _] = ModelFixture.requests(context.fixture)
  end

  test "pending plugin settings fence fresh injections while preserving earlier history",
       context do
    {pid, plugin, skill} = installed(context)
    thread = thread(context, pid)

    input = [
      text("Complete this synthetic selection"),
      %{"type" => "skill", "name" => skill["name"], "path" => skill["path"]},
      mention(plugin)
    ]

    for {disabled, expected} <- [{[], 1}, {[plugin], 1}, {[], 2}] do
      assert call(pid, "thread/settings/update", %{
               "threadId" => thread,
               "disabledPluginIds" => disabled
             }) == %{}

      turn = start_turn(pid, thread, input)
      events = finish_turn(pid, thread, turn)
      assert_user_content(events, thread, turn, input)
      request = List.last(ModelFixture.requests(context.fixture))
      assert count_messages(request, "developer", @hint) == expected
      assert count_messages(request, "user", @marker) == expected
    end

    [first, _, _] = ModelFixture.requests(context.fixture)
    skill_position = message_position(first, "user", @marker)
    hint_position = message_position(first, "developer", @hint)
    assert is_integer(skill_position) and is_integer(hint_position)
    assert skill_position < hint_position
    assert :ok = Session.close(pid)
    resumed = start(context)
    assert call(resumed, "thread/resume", %{"threadId" => thread})["thread"]["id"] == thread
    assert [_, _, _] = ModelFixture.requests(context.fixture)
  end

  defp installed(context) do
    pid = start(context)

    listing =
      call(pid, "plugin/list", %{
        "cwds" => [context.fixture.workspace],
        "marketplaceKinds" => ["local"],
        "forceRefetch" => false
      })

    assert listing["marketplaceLoadErrors"] == []
    assert Enum.any?(listing["marketplaces"], &(&1["name"] == "fixture-market"))
    params = %{"marketplacePath" => context.marketplace, "pluginName" => @name}
    assert call(pid, "plugin/install", params)["appsNeedingAuth"] == []
    detail = call(pid, "plugin/read", params)["plugin"]
    assert %{"installed" => true, "enabled" => true, "id" => id} = detail["summary"]
    assert id == "#{@name}@fixture-market"
    assert [%{"enabled" => true}] = detail["skills"]

    # Plugin detail describes the package. Select the current runtime catalog's
    # namespaced skill and installed path, rather than its source-package path.
    skills =
      call(pid, "skills/list", %{"cwds" => [context.fixture.workspace], "forceReload" => true})[
        "data"
      ]
      |> Enum.flat_map(& &1["skills"])
      |> Enum.filter(&String.starts_with?(&1["name"], @name <> ":"))

    assert [%{"enabled" => true, "name" => name, "path" => path}] = skills
    assert File.regular?(path)
    {pid, id, %{"name" => name, "path" => path}}
  end

  defp mention(id),
    do: %{"type" => "mention", "name" => "Unrelated display label", "path" => "plugin://#{id}"}

  defp text(value), do: %{"type" => "text", "text" => value}

  defp assert_user_content(events, thread, turn, input) do
    for method <- ["item/started", "item/completed"] do
      params =
        notification(events, method, fn params ->
          params["threadId"] == thread and params["turnId"] == turn and
            params["item"]["type"] == "userMessage"
        end)

      content = params["item"]["content"]
      Enum.each(input, &assert_user_item(content, &1, input))
    end
  end

  defp assert_user_item(content, %{"type" => "text"} = item, _input),
    do: assert(Enum.any?(content, &(&1["type"] == "text" and &1["text"] == item["text"])))

  defp assert_user_item(content, item, input),
    do: assert(Enum.count(content, &(&1 == item)) == Enum.count(input, &(&1 == item)))

  defp contains?(item, role, marker),
    do:
      item["role"] == role and
        Enum.any?(
          Map.get(item, "content", []),
          &String.contains?(Map.get(&1, "text", ""), marker)
        )

  defp count_messages(request, role, marker),
    do: Enum.count(request["input"], &contains?(&1, role, marker))

  defp message_position(request, role, marker),
    do: Enum.find_index(request["input"], &contains?(&1, role, marker))
end
