defmodule SamgitaCodexDriver.NativeOrdinarySummaryGitTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 90_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_summary_git_fixture.py", __DIR__)
  @script_sha "d0c6f2a6e2466757a43c6f44f6c94a82a3285564214870e3f5843aefa7e67ecd"
  @cleanup Path.join(__DIR__, "support/stdio_session_fixture.ex")
  @cleanup_sha "a164a57adff4cba26360a7e2788b8c3e9e6829a0a5e77eae28e857c29dc201a0"
  @launch Path.join(__DIR__, "support/native_launch_fixture.ex")
  @launch_sha "98126d19e19230d44817249684ec5dfb3778b5acd73271434ae6b83cb566da08"
  @schema_pins [
    {"experimental/ClientRequest.json",
     "92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352"},
    {"supplemental/ClientRequest.json",
     "072f0e33f3458e5493df30d93dea6cc437cd2eef758db5a07b47813b5d9c5708"},
    {"supplemental/v1/ConversationGitInfo.json",
     "98f1faa58f184e8239e11bda21094b5cd4e324d73b806b9af75bf67d9b32e21f"},
    {"supplemental/v1/ConversationSummary.json",
     "2ba2ae3981c856fc67be1fad93a6d7d38ef453db28aad663ceeab3dd10512a1e"}
  ]
  # Physical nodes of the locally derived supplement, not official JSON export.
  # Each canonical JSON byte string/hash is copied from immutable d08fa36 owner data.
  @physical [
    {3219, "supplemental/ClientRequest.json", "/oneOf/0",
     "79e2083ede3a9407b4e697504d83817d23f207a48e91603f47133eb23fad7e97",
     "{\n  \"properties\": {\n    \"id\": {\n      \"$ref\": \"#/definitions/RequestId\"\n    },\n    \"method\": {\n      \"enum\": [\n        \"getConversationSummary\"\n      ],\n      \"type\": \"string\"\n    },\n    \"params\": {\n      \"$ref\": \"#/definitions/GetConversationSummaryParams\"\n    }\n  },\n  \"required\": [\n    \"id\",\n    \"method\",\n    \"params\"\n  ],\n  \"title\": \"GetConversationSummaryRequest\",\n  \"type\": \"object\"\n}\n"},
    {3220, "supplemental/ClientRequest.json", "/oneOf/0/properties/id",
     "f1fb3724bb7835add8ed79ef8a7e1acaf3c9c5761502e6ae54c85d0c7f6c82e7",
     "{\n  \"$ref\": \"#/definitions/RequestId\"\n}\n"},
    {3221, "supplemental/ClientRequest.json", "/oneOf/0/properties/method",
     "c08ab28960d64928aca1226e3f946b06a41f70e7d940443c7ac31682ecba9910",
     "{\n  \"enum\": [\n    \"getConversationSummary\"\n  ],\n  \"type\": \"string\"\n}\n"},
    {3222, "supplemental/ClientRequest.json", "/oneOf/0/properties/method/enum/0",
     "fcf3437ca4a2985db84f72e8d14385723873fcd5bc33787442e9cad9e64d5285",
     "\"getConversationSummary\"\n"},
    {3223, "supplemental/ClientRequest.json", "/oneOf/0/properties/params",
     "fbe0b2b1191b449f8b7a7ea14527856895f6eae86832550f2335c59a057baa60",
     "{\n  \"$ref\": \"#/definitions/GetConversationSummaryParams\"\n}\n"},
    {3224, "supplemental/ClientRequest.json", "/oneOf/1",
     "dc2c12d770e311753be0a92cd63fb07c88e8daca505a3416bc5848fe5f93b39c",
     "{\n  \"properties\": {\n    \"id\": {\n      \"$ref\": \"#/definitions/RequestId\"\n    },\n    \"method\": {\n      \"enum\": [\n        \"gitDiffToRemote\"\n      ],\n      \"type\": \"string\"\n    },\n    \"params\": {\n      \"$ref\": \"#/definitions/GitDiffToRemoteParams\"\n    }\n  },\n  \"required\": [\n    \"id\",\n    \"method\",\n    \"params\"\n  ],\n  \"title\": \"GitDiffToRemoteRequest\",\n  \"type\": \"object\"\n}\n"},
    {3225, "supplemental/ClientRequest.json", "/oneOf/1/properties/id",
     "f1fb3724bb7835add8ed79ef8a7e1acaf3c9c5761502e6ae54c85d0c7f6c82e7",
     "{\n  \"$ref\": \"#/definitions/RequestId\"\n}\n"},
    {3226, "supplemental/ClientRequest.json", "/oneOf/1/properties/method",
     "0632017eb5e972b72e0185f47eee18d3060a990f827137a2c4e2ae257628a349",
     "{\n  \"enum\": [\n    \"gitDiffToRemote\"\n  ],\n  \"type\": \"string\"\n}\n"},
    {3227, "supplemental/ClientRequest.json", "/oneOf/1/properties/method/enum/0",
     "1bd314a1a63a969a496546ec5722e1f41ead9fa8a8c3dec74d9e105c0f0e135c", "\"gitDiffToRemote\"\n"},
    {3228, "supplemental/ClientRequest.json", "/oneOf/1/properties/params",
     "ba3d51d2065e4f831a87feee5be761a72735b4711bd739e34fea8c766fcbd9c1",
     "{\n  \"$ref\": \"#/definitions/GitDiffToRemoteParams\"\n}\n"},
    {3243, "supplemental/v1/ConversationGitInfo.json", "/properties/branch",
     "2d0b6ec9f2b2decf1e1e919f3b0c593315f5164871c5ab7d0565e6bf3d3acb08",
     "{\n  \"anyOf\": [\n    {\n      \"type\": \"string\"\n    },\n    {\n      \"type\": \"null\"\n    }\n  ]\n}\n"},
    {3244, "supplemental/v1/ConversationGitInfo.json", "/properties/branch/anyOf/0",
     "bf0b727f7b1c6d07c7312c6c7760fd34302744385611a86804210c77d80b0cc7",
     "{\n  \"type\": \"string\"\n}\n"},
    {3245, "supplemental/v1/ConversationGitInfo.json", "/properties/branch/anyOf/1",
     "b7c373d0981a5441c9dd775ad89a68ba691af04e4da70eaeaacaaf54549837fb",
     "{\n  \"type\": \"null\"\n}\n"},
    {3246, "supplemental/v1/ConversationGitInfo.json", "/properties/origin_url",
     "2d0b6ec9f2b2decf1e1e919f3b0c593315f5164871c5ab7d0565e6bf3d3acb08",
     "{\n  \"anyOf\": [\n    {\n      \"type\": \"string\"\n    },\n    {\n      \"type\": \"null\"\n    }\n  ]\n}\n"},
    {3247, "supplemental/v1/ConversationGitInfo.json", "/properties/origin_url/anyOf/0",
     "bf0b727f7b1c6d07c7312c6c7760fd34302744385611a86804210c77d80b0cc7",
     "{\n  \"type\": \"string\"\n}\n"},
    {3248, "supplemental/v1/ConversationGitInfo.json", "/properties/origin_url/anyOf/1",
     "b7c373d0981a5441c9dd775ad89a68ba691af04e4da70eaeaacaaf54549837fb",
     "{\n  \"type\": \"null\"\n}\n"},
    {3249, "supplemental/v1/ConversationGitInfo.json", "/properties/sha",
     "2d0b6ec9f2b2decf1e1e919f3b0c593315f5164871c5ab7d0565e6bf3d3acb08",
     "{\n  \"anyOf\": [\n    {\n      \"type\": \"string\"\n    },\n    {\n      \"type\": \"null\"\n    }\n  ]\n}\n"},
    {3250, "supplemental/v1/ConversationGitInfo.json", "/properties/sha/anyOf/0",
     "bf0b727f7b1c6d07c7312c6c7760fd34302744385611a86804210c77d80b0cc7",
     "{\n  \"type\": \"string\"\n}\n"},
    {3251, "supplemental/v1/ConversationGitInfo.json", "/properties/sha/anyOf/1",
     "b7c373d0981a5441c9dd775ad89a68ba691af04e4da70eaeaacaaf54549837fb",
     "{\n  \"type\": \"null\"\n}\n"},
    {3256, "supplemental/v1/ConversationSummary.json", "/properties/gitInfo/anyOf/0",
     "2ddf1cf4368581dafdf7419d8415ee56dc600b4037141ec6bd6e29da14d969c3",
     "{\n  \"$ref\": \"#/definitions/ConversationGitInfo\"\n}\n"}
  ]

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio
    alias SamgitaProtocolCodex.Error

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, bytes) do
      case Stdio.send(state, bytes) do
        {:ok, next} ->
          case record(next, :out, bytes) do
            :ok -> {:ok, next}
            {:error, error} -> {:error, error, next}
          end

        other ->
          other
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          case record_events(next, events) do
            :ok -> {:ok, events, next}
            {:error, error} -> {:error, error, next}
          end

        other ->
          other
      end
    end

    defp record_events(state, events) do
      Enum.reduce_while(events, :ok, fn
        {:message, bytes}, :ok ->
          case record(state, :in, bytes) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end

        _, :ok ->
          {:cont, :ok}
      end)
    end

    defp record(state, direction, bytes) do
      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(bytes)
        limit = if direction == :out, do: 16_384, else: 262_144

        if length(ledger.frames) < 256 and size <= limit and ledger.bytes + size <= 4_194_304 do
          frame = %{direction: direction, encoded: bytes, wire: JSON.decode!(bytes)}
          {:ok, %{ledger | frames: ledger.frames ++ [frame], bytes: ledger.bytes + size}}
        else
          {{:error, Error.new(:test_capture_overflow)}, ledger}
        end
      end)
    end

    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) === @binary_sha

    for {path, sha} <- [{@script, @script_sha}, {@cleanup, @cleanup_sha}, {@launch, @launch_sha}],
        do: assert(hash(File.read!(path)) === sha)

    for {path, sha} <- @schema_pins, do: assert(hash(File.read!(schema_path(path))) === sha)
    python = System.find_executable("python3") || flunk("BLOCKED_ENV: Python 3 required")
    git = System.find_executable("git") || flunk("BLOCKED_ENV: Git required")

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-ordinary-summary-git-" <>
          Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      )

    File.mkdir!(root)
    resources = :atomics.new(3, [])

    on_exit(fn ->
      assert Enum.all?(1..3, &(:atomics.get(resources, &1) in [0, 2])),
             "Owned cleanup unconfirmed; retaining summary/Git fixture #{root}"

      File.rm_rf!(root)
    end)

    for child <- ~w(home codex workspace tmp), do: File.mkdir!(Path.join(root, child))

    capture =
      start_supervised!({Agent, fn -> %{frames: [], bytes: 0, owners: MapSet.new()} end})

    ctx = %{
      root: root,
      binary: Path.expand(binary),
      python: Path.expand(python),
      git: Path.expand(git),
      home: Path.join(root, "home"),
      codex: Path.join(root, "codex"),
      workspace: Path.join(root, "workspace"),
      resources: resources,
      capture: capture
    }

    helper = start_helper(ctx)
    facts = helper.facts
    assert facts["dirty"] === false
    assert facts["named"]["branch"] === "main"
    assert facts["named"]["origin_url"] === "https://example.invalid/owned-summary.git"
    assert facts["detached"]["branch"] === nil and facts["detached"]["origin_url"] === nil
    assert facts["unborn"]["sha"] === nil and facts["unborn"]["branch"] === nil
    assert facts["unborn"]["origin_url"] === "https://example.invalid/owned-unborn.git"

    for key <- ~w(named detached), do: assert(facts[key]["sha"] =~ ~r/\A[0-9a-f]{40}\z/)

    inputs =
      [
        @script,
        @cleanup,
        @launch,
        Path.join(ctx.codex, "config.toml"),
        Path.join(ctx.codex, "models.json")
      ] ++ Enum.map(@schema_pins, fn {path, _} -> schema_path(path) end)

    Map.merge(ctx, %{helper: helper, facts: facts, inputs: Map.new(inputs, &{&1, snapshot(&1)})})
  end

  test "native supplemental summaries preserve real Git facts and diff envelopes across cold reads",
       ctx do
    warm = start_native(ctx, 2)
    assert_empty_loaded(ctx, warm.pid)

    histories =
      for key <- ~w(named detached unborn) do
        fact = ctx.facts[key]
        assert String.starts_with?(fact["cwd"], ctx.root <> "/")

        # This narrow profile never calls TurnFixture.thread/3 and never sends a turn.
        thread =
          call(ctx, warm.pid, "thread/start", %{
            "model" => "mock-model",
            "modelProvider" => "fixture",
            "cwd" => fact["cwd"],
            "ephemeral" => false,
            "historyMode" => "paginated"
          })["thread"]

        id = thread["id"]
        assert is_binary(id) and byte_size(id) > 0

        assert call(ctx, warm.pid, "thread/name/set", %{
                 "threadId" => id,
                 "name" => "Owned #{key} summary λ"
               }) === %{}

        native = call(ctx, warm.pid, "thread/read", %{"threadId" => id})["thread"]
        path = native["path"]
        assert is_binary(path) and String.starts_with?(Path.expand(path), ctx.codex <> "/")
        assert File.regular?(path)
        stored = snapshot(path)
        by_id = summary(ctx, warm.pid, %{"conversationId" => id})
        assert_summary(ctx, by_id, id, fact, path)
        assert summary(ctx, warm.pid, %{"rolloutPath" => path}) === by_id
        relative = Path.relative_to(path, ctx.codex)
        refute Path.type(relative) === :absolute
        assert summary(ctx, warm.pid, %{"rolloutPath" => relative}) === by_id
        assert snapshot(path) === stored
        %{id: id, summary: by_id, path: path, stored: stored}
      end

    repo = ctx.facts["named"]["cwd"]
    base = ctx.facts["named"]["sha"]

    assert call(ctx, warm.pid, "gitDiffToRemote", %{"cwd" => repo}) === %{
             "sha" => base,
             "diff" => ""
           }

    assert helper_call(ctx.helper, %{"op" => "dirty"}, 1, 5_000) === %{
             "dirty" => true,
             "tracked" => "changed λ\n",
             "untracked" => "untracked 🙂\n"
           }

    assert File.read!(Path.join(repo, "tracked.txt")) === "changed λ\n"
    assert File.read!(Path.join(repo, "new.txt")) === "untracked 🙂\n"
    dirty = call(ctx, warm.pid, "gitDiffToRemote", %{"cwd" => repo})
    assert Enum.sort(Map.keys(dirty)) === ["diff", "sha"]
    assert dirty["sha"] === base
    assert dirty["diff"] =~ "diff --git a/tracked.txt b/tracked.txt\n"
    assert dirty["diff"] =~ "-original\n+changed λ\n"
    assert dirty["diff"] =~ "diff --git a/new.txt b/new.txt\nnew file mode 100644\n"
    assert dirty["diff"] =~ "+untracked 🙂\n"
    assert call(ctx, warm.pid, "gitDiffToRemote", %{"cwd" => repo}) === dirty
    assert_idle(warm.pid)
    before_close = frames(ctx)
    close_native(warm)
    assert frames(ctx) === before_close

    cold = start_native(ctx, 3)
    assert_empty_loaded(ctx, cold.pid)

    for history <- histories do
      assert summary(ctx, cold.pid, %{"conversationId" => history.id}) === history.summary
      assert snapshot(history.path) === history.stored
    end

    assert_idle(cold.pid)
    assert_inputs(ctx)
    verified = helper_call(ctx.helper, %{"op" => "verify"}, 2, 12_000)
    assert verified["dirty"] === true

    assert Map.drop(verified, ["dirty", "commands"]) ===
             Map.drop(ctx.facts, ["dirty", "commands"])

    assert length(verified["commands"]) <= 48
    assert_inventory(ctx)
    assert Agent.get(ctx.capture, & &1.owners) === MapSet.new(Enum.map(@physical, &elem(&1, 0)))
    before_close = frames(ctx)
    close_native(cold)
    assert frames(ctx) === before_close
    close_helper(ctx.helper)
    assert_inputs(ctx)
  end

  defp summary(ctx, pid, params) do
    result = call(ctx, pid, "getConversationSummary", params)
    assert Enum.sort(Map.keys(result)) === ["summary"]
    result["summary"]
  end

  defp assert_summary(ctx, summary, id, fact, path) do
    assert is_map(summary)

    assert Map.take(summary, ~w(conversationId cwd path preview modelProvider)) === %{
             "conversationId" => id,
             "cwd" => fact["cwd"],
             "path" => path,
             "preview" => "",
             "modelProvider" => "fixture"
           }

    expected = Map.take(fact, ~w(sha branch origin_url))
    observed = Map.fetch!(summary, "gitInfo")
    assert observed === expected
    assert :ok = Schema.validate(schema("supplemental/v1/ConversationSummary.json"), summary)
    bind(ctx, 3256, observed)

    for {field, parent} <- [{"branch", 3243}, {"origin_url", 3246}, {"sha", 3249}] do
      value = Map.fetch!(observed, field)
      assert value === Map.fetch!(expected, field)
      bind(ctx, parent, value)
      bind(ctx, if(is_nil(value), do: parent + 2, else: parent + 1), value)
    end
  end

  defp bind(ctx, index, value) do
    {^index, path, pointer, sha, encoded} = Enum.find(@physical, &(elem(&1, 0) === index))
    assert hash(encoded) === sha
    document = schema(path)
    node = at_pointer(document, pointer)
    assert JSON.decode!(encoded) === node

    contract =
      if is_map(node),
        do: Map.put(node, "definitions", Map.fetch!(document, "definitions")),
        else: %{"enum" => [node]}

    assert :ok = Schema.validate(contract, value, max_depth: 64)
    Agent.update(ctx.capture, &%{&1 | owners: MapSet.put(&1.owners, index)})
  end

  defp at_pointer(document, pointer) do
    pointer
    |> String.trim_leading("/")
    |> String.split("/")
    |> Enum.reduce(document, fn segment, current ->
      key = segment |> String.replace("~1", "/") |> String.replace("~0", "~")

      if is_list(current),
        do: Enum.fetch!(current, String.to_integer(key)),
        else: Map.fetch!(current, key)
    end)
  end

  defp bind_request(ctx, wire) do
    branch = if wire["method"] === "getConversationSummary", do: 3219, else: 3224
    bind(ctx, branch, wire)
    bind(ctx, branch + 1, Map.fetch!(wire, "id"))
    bind(ctx, branch + 2, Map.fetch!(wire, "method"))
    bind(ctx, branch + 3, Map.fetch!(wire, "method"))
    bind(ctx, branch + 4, Map.fetch!(wire, "params"))
  end

  defp start_native(ctx, slot) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 128,
               max_event_bytes: 2_097_152,
               max_message_bytes: 262_144,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.workspace,
                    inherit_env: [],
                    max_message_bytes: 262_144,
                    env: native_env(ctx)
                  ]}
             )

    :atomics.put(ctx.resources, slot, 1)
    %{connection: connection} = :sys.get_state(pid)
    identity = :atomics.new(1, [])

    native = %{
      pid: pid,
      connection: connection,
      identity: identity,
      resources: ctx.resources,
      slot: slot
    }

    on_exit(fn -> close_native(native) end)
    id = request_id()
    info = %{"name" => "owned_ordinary_summary_git", "version" => "1"}
    capabilities = %{"experimentalApi" => true}

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(
      ctx,
      %{
        "id" => id,
        "method" => "initialize",
        "params" => %{"clientInfo" => info, "capabilities" => capabilities}
      },
      response
    )

    os_pid = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(os_pid) and os_pid > 0
    :atomics.put(identity, 1, os_pid)
    assert hash(File.read!("/proc/#{os_pid}/exe")) === @binary_sha
    native
  end

  defp native_env(ctx) do
    %{
      "HOME" => ctx.home,
      "CODEX_HOME" => ctx.codex,
      "TMPDIR" => Path.join(ctx.root, "tmp"),
      "PATH" => Path.dirname(ctx.git) <> ":/usr/bin:/bin",
      "SHELL" => "/bin/sh",
      "NO_PROXY" => "*",
      "no_proxy" => "*",
      "NO_COLOR" => "1",
      "RUST_LOG" => "off",
      "PYTHONDONTWRITEBYTECODE" => "1",
      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
      "GIT_CONFIG_NOSYSTEM" => "1",
      "GIT_CONFIG_GLOBAL" => "/dev/null",
      "GIT_TERMINAL_PROMPT" => "0"
    }
  end

  defp call(ctx, pid, method, params) do
    id = request_id()
    wire = %{"id" => id, "method" => method, "params" => params}
    legacy? = method in ["getConversationSummary", "gitDiffToRemote"]

    root =
      if legacy?, do: "supplemental/ClientRequest.json", else: "experimental/ClientRequest.json"

    assert :ok = Schema.validate(schema(root), wire, max_depth: 64)

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    if legacy?, do: bind_request(ctx, wire)
    result
  end

  defp assert_exchange(ctx, wire, response) do
    assert [sent] =
             Enum.filter(frames(ctx), &(&1.direction === :out and &1.wire["id"] === wire["id"]))

    assert [received] =
             Enum.filter(frames(ctx), &(&1.direction === :in and &1.wire["id"] === wire["id"]))

    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert {:ok, decoded} = Wire.decode(received.encoded, max_depth: 64)
    assert decoded === response and Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp assert_empty_loaded(ctx, pid),
    do: assert(call(ctx, pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil})

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert Session.uncertain_operations(pid) === []
  end

  defp assert_inventory(ctx) do
    warm =
      (~w(initialize initialized server/diagnostics thread/loaded/list) ++
         List.duplicate(
           ~w(thread/start thread/name/set thread/read getConversationSummary getConversationSummary getConversationSummary),
           3
         ))
      |> List.flatten()

    expected =
      warm ++
        ~w(gitDiffToRemote gitDiffToRemote gitDiffToRemote initialize initialized server/diagnostics thread/loaded/list getConversationSummary getConversationSummary getConversationSummary)

    outgoing = Enum.filter(frames(ctx), &(&1.direction === :out))
    assert Enum.map(outgoing, & &1.wire["method"]) === expected
    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 30 and length(Enum.uniq(ids)) === 30
    replies = Enum.filter(frames(ctx), &(&1.direction === :in and Map.has_key?(&1.wire, "id")))
    assert length(replies) === 30
    assert MapSet.new(Enum.map(replies, & &1.wire["id"])) === MapSet.new(ids)
  end

  defp start_helper(ctx) do
    assert {:ok, transport} =
             Stdio.open(
               executable: ctx.python,
               args: [@script, "--root", ctx.root, "--git", ctx.git],
               cwd: ctx.workspace,
               inherit_env: [],
               max_message_bytes: 16_384,
               env: native_env(ctx)
             )

    :atomics.put(ctx.resources, 1, 1)
    identity = :atomics.new(1, [])
    helper = %{transport: transport, identity: identity, resources: ctx.resources}
    on_exit(fn -> close_helper(helper) end)
    startup = helper_line(transport.port, <<>>, now() + 18_000)
    os_pid = startup["pid"]
    assert is_integer(os_pid) and os_pid > 0
    :atomics.put(identity, 1, os_pid)
    assert hash(File.read!("/proc/#{os_pid}/exe")) === hash(File.read!(ctx.python))
    Map.put(helper, :facts, Map.fetch!(startup, "facts"))
  end

  defp helper_call(helper, request, sequence, timeout_ms) do
    assert {:ok, _} = Stdio.send(helper.transport, JSON.encode!(request))

    assert %{"sequence" => ^sequence, "result" => result} =
             helper_line(helper.transport.port, <<>>, now() + timeout_ms)

    result
  end

  defp helper_line(port, bytes, deadline) do
    remaining = deadline - now()
    assert remaining > 0 and byte_size(bytes) <= 16_384, "Owned scratch-Git response bound"

    case String.split(bytes, "\n", parts: 2) do
      [line, ""] ->
        JSON.decode!(line)

      [_line, _extra] ->
        flunk("Unexpected scratch-Git output")

      [_partial] ->
        receive do
          {^port, {:data, chunk}} -> helper_line(port, bytes <> chunk, deadline)
          {^port, {:exit_status, status}} -> flunk("Owned scratch-Git helper exited #{status}")
        after
          remaining -> flunk("Owned scratch-Git helper response deadline")
        end
    end
  end

  defp close_native(native) do
    monitor = Process.monitor(native.connection.owner.pid)
    assert :ok = StdioSessionFixture.close(native.pid, native.connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert_closed(native.connection, native.identity)
    :atomics.put(native.resources, native.slot, 2)
  end

  defp close_helper(helper) do
    monitor = Process.monitor(helper.transport.owner.pid)
    assert :ok = Stdio.close(helper.transport)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert_closed(helper.transport, helper.identity)
    :atomics.put(helper.resources, 1, 2)
  end

  defp assert_closed(connection, identity) do
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert Port.info(connection.port) === nil
    os_pid = :atomics.get(identity, 1)
    if os_pid > 0, do: refute(File.exists?("/proc/#{os_pid}"))
  end

  defp assert_inputs(ctx) do
    for {path, before} <- ctx.inputs, do: assert(snapshot(path) === before)
    assert File.ls!(ctx.workspace) === []
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp frames(ctx), do: Agent.get(ctx.capture, & &1.frames)
  defp schema(path), do: schema_path(path) |> File.read!() |> JSON.decode!()

  defp schema_path(path),
    do: :samgita_protocol_codex |> :code.priv_dir() |> Path.join("upstream/0.163.0/" <> path)

  defp request_id,
    do: "owned-ordinary-summary-git-#{System.unique_integer([:positive, :monotonic])}"

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
