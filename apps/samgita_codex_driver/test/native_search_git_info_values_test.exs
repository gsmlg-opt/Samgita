defmodule SamgitaCodexDriver.NativeSearchGitInfoValuesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @needle "Owned native search GitInfo λ marker"
  @instructions "Owned fixed search GitInfo fixture instructions."
  @answer "Deterministic local fixture answer"
  @subject %{
    "sha" => "abc123",
    "branch" => "feature/search-git-λ",
    "originUrl" => "https://example.invalid/owned/subject.git"
  }
  @control %{
    "sha" => "fed987",
    "branch" => "control/search-git",
    "originUrl" => "https://example.invalid/owned/control.git"
  }

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      wire = JSON.decode!(encoded)

      if wire["method"] in ["thread/metadata/update", "thread/search"] do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 16 and byte_size(encoded) <= 4096 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [wire]))
          {:ok, next}
        end
      else
        {:error, SamgitaProtocolCodex.Error.new(:test_capture_overflow), state}
      end
    end

    @impl true
    def handle_info(message, state), do: Stdio.handle_info(message, state)
    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup tags do
    ctx = TurnFixture.setup(tags)
    assert hash(File.read!(ctx.binary)) == @binary_sha

    TurnFixture.configure_model(ctx, %{
      "model_messages" => %{"instructions_template" => @instructions}
    })

    # Content search uses the real local executable in the owned fixture PATH.
    rg = System.find_executable("rg")
    assert is_binary(rg) and File.regular?(rg), "BLOCKED_ENV: ripgrep required"
    File.ln_s!(rg, Path.join(ctx.fixture.bin, "rg"))
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(model_reasoning_effort = "low"\nmodel_reasoning_summary = "auto"\n) <>
        ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    capture = start_supervised!({Agent, fn -> [] end})
    Map.merge(ctx, %{capture: capture, config: config, config_bytes: File.read!(config)})
  end

  test "native content search projects full and partially cleared GitInfo only onto its owning thread",
       ctx do
    pid = start(ctx)
    subject = complete(ctx, pid, "subject", 1)
    control = complete(ctx, pid, "control", 2)
    assert subject.id != control.id
    assert subject.path != control.path
    saved = [subject, control]
    journal = File.read!(ctx.fixture.requests)
    update(ctx, pid, control.id, @control, @control)

    for {patch, expected} <- subject_cases() do
      update(ctx, pid, subject.id, patch, expected)
      assert_search(ctx, pid, saved, %{subject.id => expected, control.id => @control})
      assert_retained(ctx, pid, saved, %{subject.id => expected, control.id => @control}, journal)
    end

    captures = Agent.get(ctx.capture, & &1)
    assert Enum.count(captures, &(&1["method"] == "thread/metadata/update")) == 5
    assert Enum.count(captures, &(&1["method"] == "thread/search")) == 4
    assert :ok = close(pid)
  end

  # Every expected object is independently prescribed. The nulls belong to
  # child fields of a real GitInfo object, never a null parent projection.
  defp subject_cases do
    [
      {@subject, @subject},
      {%{"sha" => nil},
       %{
         "sha" => nil,
         "branch" => "feature/search-git-λ",
         "originUrl" => "https://example.invalid/owned/subject.git"
       }},
      {%{"branch" => nil},
       %{
         "sha" => nil,
         "branch" => nil,
         "originUrl" => "https://example.invalid/owned/subject.git"
       }},
      {%{"sha" => "def456", "originUrl" => nil},
       %{"sha" => "def456", "branch" => nil, "originUrl" => nil}}
    ]
  end

  defp complete(ctx, pid, suffix, count) do
    thread =
      TurnFixture.call(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "ephemeral" => false,
        "historyMode" => "paginated"
      })["thread"]

    id = Map.fetch!(thread, "id")
    text = suffix <> " " <> @needle

    turn =
      TurnFixture.call(pid, "turn/start", %{
        "threadId" => id,
        "input" => [%{"type" => "text", "text" => text}]
      })["turn"]["id"]

    events = complete_turn(pid, id, turn, [], deadline(20_000))
    items = completed_items(events, id, turn, text)
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == count
    assert_provider(List.last(requests), text)

    # Observe the supported public full-history view without treating a read
    # as a general durability/flush guarantee or polling content into existence.
    history = read(pid, id)
    assert Map.fetch!(history, "historyMode") == "paginated"
    assert Map.fetch!(history, "preview") == text
    assert [%{"id" => ^turn, "status" => "completed", "items" => ^items}] = history["turns"]
    path = Map.fetch!(history, "path")
    assert File.regular?(path)
    %{id: id, turn: turn, text: text, items: items, turns: history["turns"], path: path}
  end

  defp update(ctx, pid, thread, patch, expected) do
    result =
      request(ctx, pid, "thread/metadata/update", %{"threadId" => thread, "gitInfo" => patch})

    updated = Map.fetch!(result, "thread")
    assert Map.fetch!(updated, "id") == thread
    assert Map.fetch!(updated, "gitInfo") === expected
  end

  defp assert_search(ctx, pid, saved, expected) do
    result = request(ctx, pid, "thread/search", %{"searchTerm" => @needle, "limit" => 10})
    assert Map.fetch!(result, "nextCursor") == nil
    rows = Map.fetch!(result, "data")
    assert length(rows) == 2
    by_id = Map.new(saved, &{&1.id, &1})
    assert Enum.sort(Enum.map(rows, & &1["thread"]["id"])) == Enum.sort(Map.keys(by_id))

    for row <- rows do
      thread = Map.fetch!(row, "thread")
      id = Map.fetch!(thread, "id")
      original = Map.fetch!(by_id, id)
      assert Map.fetch!(row, "snippet") == original.text
      assert Map.fetch!(thread, "preview") == original.text
      assert Map.fetch!(thread, "path") == original.path
      assert Map.fetch!(thread, "historyMode") == "paginated"
      assert Map.fetch!(thread, "turns") == []
      assert Map.fetch!(thread, "gitInfo") === Map.fetch!(expected, id)
    end
  end

  defp assert_retained(ctx, pid, saved, expected, journal) do
    for original <- saved do
      history = read(pid, original.id)
      assert Map.fetch!(history, "id") == original.id
      assert Map.fetch!(history, "path") == original.path
      assert Map.fetch!(history, "preview") == original.text
      assert Map.fetch!(history, "turns") === original.turns
      assert Map.fetch!(history, "gitInfo") === Map.fetch!(expected, original.id)
      assert File.regular?(original.path)
    end

    assert File.read!(ctx.fixture.requests) == journal
    assert length(ModelFixture.requests(ctx.fixture)) == 2
    assert File.read!(ctx.config) == ctx.config_bytes
    assert File.ls!(ctx.fixture.workspace) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
  end

  defp request(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-search-git-info-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, method, params, id: id)

    assert [wire] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert wire === %{"id" => id, "method" => method, "params" => params}
    result
  end

  defp completed_items(events, thread, turn, text) do
    items =
      for event <- events,
          event.wire["method"] == "item/completed",
          event.wire["params"]["threadId"] == thread,
          event.wire["params"]["turnId"] == turn,
          do: Map.fetch!(event.wire["params"], "item")

    assert Enum.map(items, & &1["type"]) == ["userMessage", "agentMessage"]
    [user, assistant] = items

    assert Map.fetch!(user, "content") == [
             %{"type" => "text", "text" => text, "text_elements" => []}
           ]

    assert Map.fetch!(assistant, "text") == @answer
    assert Enum.all?(items, &(is_binary(&1["id"]) and &1["id"] != ""))
    assert user["id"] != assistant["id"]
    items
  end

  defp assert_provider(request, text) do
    assert request["model"] == "mock-model"

    assert %{
             "role" => "developer",
             "content" => [%{"type" => "input_text", "text" => @instructions}]
           } = hd(request["input"])

    user_texts =
      for item <- request["input"],
          item["role"] == "user",
          content <- item["content"],
          content["type"] == "input_text",
          do: content["text"]

    assert Enum.count(user_texts, &(&1 == text)) == 1
  end

  defp complete_turn(pid, thread, turn, events, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256, "Native search GitInfo event buffer exceeded its bound"

    found =
      TurnFixture.notification(events, "turn/completed", fn params ->
        params["threadId"] == thread and params["turn"]["id"] == turn
      end)

    if found do
      assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} = found
      events
    else
      assert Session.status(pid).phase == :ready
      assert System.monotonic_time(:millisecond) < until, "native search GitInfo turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} ->
          :ok

        {:codex_driver, ^pid, {:gap, _}} ->
          flunk("Unexpected event gap during search GitInfo turn")
      after
        10 -> :ok
      end

      complete_turn(pid, thread, turn, events, until)
    end
  end

  defp read(pid, thread),
    do:
      TurnFixture.call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})[
        "thread"
      ]

  defp close(pid) do
    native = TurnFixture.call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native)
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")
    :ok
  end

  defp start(ctx) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {CaptureStdio,
           [
             capture: ctx.capture,
             executable: ctx.binary,
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
             cwd: fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "TMPDIR" => ctx.root,
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    %{transport: CaptureStdio, connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_search_git_info_values", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
