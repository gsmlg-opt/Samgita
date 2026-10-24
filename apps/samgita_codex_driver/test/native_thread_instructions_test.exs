defmodule SamgitaCodexDriver.NativeThreadInstructionsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [call: 3, upstream_error: 4]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @default_base "Owned config base λ🙂\nKeep this exact base."
  @default_developer "Owned config developer λ🙂\nKeep this exact policy."
  @explicit_base "Owned explicit base λ🙂\nUse this exact base."
  @explicit_developer "Owned explicit developer λ🙂\nUse this exact policy."
  @parent_base "Owned parent base λ🙂\nRetain this parent base."
  @parent_developer "Owned parent developer λ🙂\nRetain this parent policy."
  @model_base "Synthetic local turn fixture instructions."
  @markers [
    @default_base,
    @default_developer,
    @explicit_base,
    @explicit_developer,
    @parent_base,
    @parent_developer,
    @model_base
  ]

  setup tags do
    ctx = TurnFixture.setup(tags)

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    TurnFixture.configure_model(ctx, %{})
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      "instructions = #{JSON.encode!(@default_base)}\n" <>
        "developer_instructions = #{JSON.encode!(@default_developer)}\n" <>
        "cli_auth_credentials_store = \"ephemeral\"\n" <>
        "check_for_update_on_startup = false\n" <>
        "allow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\n" <>
        "shell_snapshot = false\n"
    )

    before = File.read!(config)
    on_exit(fn -> assert File.read!(config) == before end)
    ctx
  end

  for {label, params, base, developer} <- [
        {"nonempty",
         %{
           "baseInstructions" => @explicit_base,
           "developerInstructions" => @explicit_developer
         }, @explicit_base, @explicit_developer},
        {"empty", %{"baseInstructions" => "", "developerInstructions" => ""}, "", ""},
        {"null", %{"baseInstructions" => nil, "developerInstructions" => nil}, @default_base,
         @default_developer},
        {"omitted", %{}, @default_base, @default_developer}
      ] do
    @params params
    @expected_base base
    @expected_developer developer

    test "#{label} start instructions determine the exact first provider input", ctx do
      pid = TurnFixture.start(ctx)
      id = new_thread(ctx, pid, @params)
      assert save(pid, id, "Owned fresh instruction source")["turns"] == []
      assert_no_dispatch(ctx, pid, 0)

      turn = complete(ctx, pid, id, 1)
      [request] = ModelFixture.requests(ctx.fixture)
      assert_instructions(request, @expected_base, @expected_developer)
      assert turn_ids(read(pid, id)) == [turn]
    end

    test "#{label} cold-resume instructions apply before the first persisted user turn", ctx do
      first = TurnFixture.start(ctx)
      id = new_thread(ctx, first, parent_instructions())
      saved = save(first, id, "Owned pre-turn resume source")
      assert saved["turns"] == []
      assert_no_dispatch(ctx, first, 0)
      assert :ok = Session.close(first)

      cold = TurnFixture.start(ctx)
      assert loaded(cold) == []
      assert read(cold, id)["turns"] == []
      assert loaded(cold) == []
      resumed = call(cold, "thread/resume", Map.put(@params, "threadId", id))["thread"]
      assert resumed["id"] == id
      assert resumed["turns"] == []
      assert loaded(cold) == [id]
      assert_no_dispatch(ctx, cold, 0)

      turn = complete(ctx, cold, id, 1)
      [request] = ModelFixture.requests(ctx.fixture)
      assert_instructions(request, @expected_base, @expected_developer)
      save(cold, id, "Owned completed resume source")
      assert :ok = Session.close(cold)

      reader = TurnFixture.start(ctx)
      assert loaded(reader) == []
      assert turn_ids(read(reader, id)) == [turn]
      assert loaded(reader) == []
      assert_no_dispatch(ctx, reader, 1)
    end

    test "#{label} fork instructions isolate the first child turn from its persistent parent",
         ctx do
      pid = TurnFixture.start(ctx)
      parent = new_thread(ctx, pid, parent_instructions())
      saved_parent = save(pid, parent, "Owned pre-turn fork source")
      assert saved_parent["turns"] == []
      parent_bytes = File.read!(saved_parent["path"])

      child = call(pid, "thread/fork", Map.put(@params, "threadId", parent))["thread"]
      child_id = child["id"]
      refute child_id == parent
      assert child["forkedFromId"] == parent
      assert child["turns"] == []
      assert_no_dispatch(ctx, pid, 0)

      child_turn = complete(ctx, pid, child_id, 1)
      [child_request] = ModelFixture.requests(ctx.fixture)
      assert_instructions(child_request, @expected_base, @expected_developer)
      saved_child = save(pid, child_id, "Owned completed fork child")
      refute saved_child["path"] == saved_parent["path"]
      assert read(pid, parent)["turns"] == []
      assert File.read!(saved_parent["path"]) == parent_bytes
      child_bytes = File.read!(saved_child["path"])

      parent_turn = complete(ctx, pid, parent, 2)
      [_child_request, parent_request] = ModelFixture.requests(ctx.fixture)
      assert_instructions(parent_request, @parent_base, @parent_developer)
      save(pid, parent, "Owned completed fork parent")
      assert File.read!(saved_child["path"]) == child_bytes
      assert :ok = Session.close(pid)

      cold = TurnFixture.start(ctx)
      assert loaded(cold) == []
      assert turn_ids(read(cold, parent)) == [parent_turn]
      persisted_child = read(cold, child_id)
      assert persisted_child["forkedFromId"] == parent
      assert turn_ids(persisted_child) == [child_turn]
      assert loaded(cold) == []
      assert_no_dispatch(ctx, cold, 2)
    end
  end

  for method <- ["thread/resume", "thread/fork"] do
    @method method

    test "#{method} changes the base prefix while populated developer history stays recorded",
         ctx do
      first = TurnFixture.start(ctx)
      parent = new_thread(ctx, first, parent_instructions())
      original_turn = complete(ctx, first, parent, 1)
      [original_request] = ModelFixture.requests(ctx.fixture)
      assert_instructions(original_request, @parent_base, @parent_developer)
      source = save(first, parent, "Owned populated instruction source")
      source_bytes = File.read!(source["path"])

      pid =
        if @method == "thread/resume" do
          assert :ok = Session.close(first)
          cold = TurnFixture.start(ctx)
          assert loaded(cold) == []
          cold
        else
          first
        end

      result =
        call(pid, @method, %{
          "threadId" => parent,
          "baseInstructions" => @explicit_base,
          "developerInstructions" => @explicit_developer
        })["thread"]

      id = result["id"]
      assert turn_ids(result) == [original_turn]

      if @method == "thread/resume" do
        assert id == parent
      else
        refute id == parent
        assert result["forkedFromId"] == parent
      end

      assert_no_dispatch(ctx, pid, 1)
      next_turn = complete(ctx, pid, id, 2)
      [_original_request, request] = ModelFixture.requests(ctx.fixture)

      # A completed-turn replay restores its context baseline. Generic developer
      # text is recorded initial context, not a replaceable world-state section.
      # The new base is independently prepended on every provider request.
      assert_instructions(request, @explicit_base, @parent_developer)
      assert turn_ids(read(pid, id)) == [original_turn, next_turn]

      if @method == "thread/fork" do
        assert File.read!(source["path"]) == source_bytes
        assert turn_ids(read(pid, parent)) == [original_turn]
        complete(ctx, pid, parent, 3)
        [_, _, parent_request] = ModelFixture.requests(ctx.fixture)
        assert_instructions(parent_request, @parent_base, @parent_developer)
      end
    end
  end

  test "malformed instruction types preserve loaded identities and dispatch no extra turns",
       ctx do
    pid = TurnFixture.start(ctx)
    id = new_thread(ctx, pid, parent_instructions())
    first_turn = complete(ctx, pid, id, 1)
    before = save(pid, id, "Owned malformed instruction survivor")
    assert_no_dispatch(ctx, pid, 1)
    assert loaded(pid) == [id]

    for {method, params} <- [
          {"thread/start", thread_params(ctx)},
          {"thread/resume", %{"threadId" => id}},
          {"thread/fork", %{"threadId" => id}}
        ],
        field <- ~w(baseInstructions developerInstructions),
        value <- [17, false] do
      invalid = Map.put(params, field, value)
      assert {:error, %Error{code: :schema_violation}} = Session.request(pid, method, invalid)
      error = upstream_error(pid, method, invalid, validation: :wire)
      assert error["code"] == -32_600
      assert String.starts_with?(error["message"], "Invalid request: ")
      assert error["message"] =~ "expected a string"
      assert read(pid, id) == before
      assert loaded(pid) == [id]
      events = assert_no_dispatch(ctx, pid, 1)
      refute TurnFixture.notification(events, "thread/started")
    end

    next_turn = complete(ctx, pid, id, 2)
    [_, request] = ModelFixture.requests(ctx.fixture)
    assert_instructions(request, @parent_base, @parent_developer)
    assert turn_ids(read(pid, id)) == [first_turn, next_turn]
  end

  defp parent_instructions do
    %{"baseInstructions" => @parent_base, "developerInstructions" => @parent_developer}
  end

  defp thread_params(ctx) do
    %{
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "cwd" => ctx.fixture.workspace,
      "sandbox" => "read-only",
      "approvalPolicy" => "on-request",
      "ephemeral" => false,
      "historyMode" => "legacy"
    }
  end

  defp new_thread(ctx, pid, extra),
    do: call(pid, "thread/start", Map.merge(thread_params(ctx), extra))["thread"]["id"]

  defp read(pid, id),
    do: call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]

  defp loaded(pid), do: call(pid, "thread/loaded/list", %{})["data"]
  defp turn_ids(thread), do: Enum.map(thread["turns"], & &1["id"])

  defp save(pid, id, name) do
    assert call(pid, "thread/name/set", %{"threadId" => id, "name" => name}) == %{}
    saved = read(pid, id)
    assert saved["id"] == id
    assert saved["name"] == name
    assert File.regular?(saved["path"])
    saved
  end

  defp complete(ctx, pid, id, count) do
    assert length(ModelFixture.requests(ctx.fixture)) == count - 1

    turn =
      TurnFixture.start_turn(pid, id, [
        %{"type" => "text", "text" => "Owned instruction probe λ🙂\nComplete without tools."}
      ])

    TurnFixture.finish_turn(pid, id, turn)
    assert length(ModelFixture.requests(ctx.fixture)) == count
    assert %{phase: :ready, pending: 0, uncertain: 0, interactions: 0} = Session.status(pid)
    turn
  end

  defp assert_no_dispatch(ctx, pid, count) do
    assert length(ModelFixture.requests(ctx.fixture)) == count
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, interactions: 0} = Session.status(pid)
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request))

    for method <- ["turn/started", "turn/completed", "item/started", "item/completed"] do
      refute TurnFixture.notification(events, method)
    end

    events
  end

  defp assert_instructions(request, base, developer) do
    assert request["model"] == "mock-model"
    refute Map.has_key?(request, "instructions")

    if base != "" do
      assert %{
               "type" => "message",
               "role" => "developer",
               "content" => [%{"type" => "input_text", "text" => ^base}]
             } = hd(request["input"])
    end

    # build_rendered_message keeps each developer fragment as a separate input_text
    # content item even when it combines several fragments into one message.
    developer_content =
      request["input"]
      |> Enum.filter(&(&1["role"] == "developer"))
      |> Enum.flat_map(&Map.get(&1, "content", []))

    for marker <- @markers do
      item = %{"type" => "input_text", "text" => marker}

      if marker in [base, developer] do
        assert Enum.count(developer_content, &(&1 == item)) == 1
      else
        refute item in developer_content
      end
    end
  end
end
