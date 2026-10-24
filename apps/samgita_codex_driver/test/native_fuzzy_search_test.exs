defmodule SamgitaCodexDriver.NativeFuzzySearchTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @updated "fuzzyFileSearch/sessionUpdated"
  @completed "fuzzyFileSearch/sessionCompleted"

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-fuzzy-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    Enum.each(["home", "codex", "workspace"], &File.mkdir_p!(Path.join(root, &1)))
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(Path.join(root, "codex/config.toml"), """
    model = "mock-model"
    model_provider = "fixture"
    approval_policy = "on-request"
    sandbox_mode = "read-only"
    web_search = "disabled"
    chatgpt_base_url = "http://127.0.0.1:9"
    openai_base_url = "http://127.0.0.1:9/v1"
    [features]
    shell_snapshot = false
    [model_providers.fixture]
    name = "Inert fuzzy qualification destination"
    base_url = "http://127.0.0.1:9/v1"
    wire_api = "responses"
    requires_openai_auth = false
    supports_websockets = false
    request_max_retries = 0
    stream_max_retries = 0
    """)

    %{binary: binary, root: root, workspace: Path.join(root, "workspace")}
  end

  test "one-shot ranking and character highlights match the pinned upstream fixture", ctx do
    for path <- ["abc", "abcde", "abexy", "zzz.txt", "sub/abce"], do: write(ctx.workspace, path)
    pid = start(ctx)

    assert search(pid, "abe", [ctx.workspace]) == [
             result(ctx.workspace, "abexy", "file", "abexy", 84, [0, 1, 2]),
             result(ctx.workspace, "sub/abce", "file", "abce", 72, [4, 5, 7]),
             result(ctx.workspace, "abcde", "file", "abcde", 71, [0, 1, 4])
           ]

    assert_ready(pid)
  end

  test "multiple roots preserve identity directory type and Unicode character indices", ctx do
    first = Path.join(ctx.workspace, "first")
    second = Path.join(ctx.workspace, "second")
    for root <- [first, second], do: write(root, "λ_unicode.txt")
    File.mkdir_p!(Path.join(first, "unicode_directory"))
    pid = start(ctx)
    files = search(pid, "unicode", [first, second])

    assert MapSet.new(Enum.map(files, &{&1["root"], &1["path"], &1["match_type"]})) ==
             MapSet.new([
               {first, "λ_unicode.txt", "file"},
               {second, "λ_unicode.txt", "file"},
               {first, "unicode_directory", "directory"}
             ])

    for file <- files do
      assert is_integer(file["score"]) and file["score"] > 0
      assert file["file_name"] == Path.basename(file["path"])
      assert file["indices"] == Enum.sort(Enum.uniq(file["indices"]))
      chars = String.codepoints(file["path"])
      assert Enum.map_join(file["indices"], &Enum.at(chars, &1)) == "unicode"
    end

    assert_ready(pid)
  end

  test "git context honors ignore rules while hidden files remain searchable", ctx do
    repo = Path.join(ctx.workspace, "repo")
    plain = Path.join(ctx.workspace, "plain")
    File.mkdir_p!(Path.join(repo, ".git"))

    for root <- [repo, plain] do
      write(root, ".gitignore", "ignored_needle.txt\n")
      write(root, "ignored_needle.txt")
      write(root, ".hidden_needle.txt")
      write(root, "visible_needle.txt")
    end

    pid = start(ctx)
    paths = fn root -> search(pid, "needle", [root]) |> Enum.map(& &1["path"]) |> MapSet.new() end
    assert paths.(repo) == MapSet.new([".hidden_needle.txt", "visible_needle.txt"])

    assert paths.(plain) ==
             MapSet.new([".hidden_needle.txt", "visible_needle.txt", "ignored_needle.txt"])

    assert_ready(pid)
  end

  test "one-shot empty inputs missing roots and token reuse return native results", ctx do
    write(ctx.workspace, "needle.txt")
    pid = start(ctx)
    assert search(pid, "", [ctx.workspace]) == []
    assert search(pid, "needle", []) == []
    assert search(pid, "needle", [Path.join(ctx.root, "missing")]) == []
    assert search(pid, "unmatchablezzzz", [ctx.workspace]) == []
    expected = search(pid, "needle", [ctx.workspace])
    assert [%{"path" => "needle.txt"}] = expected

    for token <- [nil, "reused-token", "reused-token"] do
      assert call(pid, "fuzzyFileSearch", %{
               "query" => "needle",
               "roots" => [ctx.workspace],
               "cancellationToken" => token
             })["files"] == expected
    end

    assert_ready(pid)
  end

  test "stream completion is idle and later case insensitive empty and clear queries remain usable",
       ctx do
    write(ctx.workspace, "alpha.txt")
    pid = start(ctx)
    begin_session(pid, "lifecycle", [ctx.workspace])
    files = query(pid, "lifecycle", "ALP", &(&1 != []))
    assert [%{"root" => root, "path" => "alpha.txt", "indices" => [0, 1, 2]}] = files
    assert root == ctx.workspace
    assert_quiet(pid, "lifecycle")
    assert query(pid, "lifecycle", "zzzz", &(&1 == [])) == []
    assert query(pid, "lifecycle", "alpha", &(&1 != [])) != []
    assert query(pid, "lifecycle", "", &(&1 == [])) == []
    assert call(pid, "fuzzyFileSearch/sessionStop", %{"sessionId" => "lifecycle"}) == %{}
    assert_ready(pid)
  end

  test "independent sessions and same-id replacement retain their own root correlation", ctx do
    first = Path.join(ctx.workspace, "first")
    second = Path.join(ctx.workspace, "second")
    write(first, "alpha.txt")
    write(second, "bravo.txt")
    pid = start(ctx)
    begin_session(pid, "first", [first])
    begin_session(pid, "second", [second])
    assert [%{"root" => ^first, "path" => "alpha.txt"}] = query(pid, "first", "alp", &(&1 != []))

    assert [%{"root" => ^second, "path" => "bravo.txt"}] =
             query(pid, "second", "bra", &(&1 != []))

    begin_session(pid, "first", [second])
    assert query(pid, "first", "alp", &(&1 == [])) == []
    assert [%{"root" => ^second, "path" => "bravo.txt"}] = query(pid, "first", "bra", &(&1 != []))
    assert [%{"root" => ^second}] = query(pid, "second", "bravo", &(&1 != []))

    for id <- ["first", "second"],
        do: assert(call(pid, "fuzzyFileSearch/sessionStop", %{"sessionId" => id}) == %{})

    assert_ready(pid)
  end

  test "stop removes a populated session rejects updates and bounds late notifications", ctx do
    for n <- 1..512, do: write(ctx.workspace, "file-#{n}.txt")
    pid = start(ctx)
    begin_session(pid, "stop", [ctx.workspace])

    assert call(pid, "fuzzyFileSearch/sessionUpdate", %{"sessionId" => "stop", "query" => "file-"}) ==
             %{}

    events =
      await(
        pid,
        &notification(&1, @updated, "stop", fn p -> p["query"] == "file-" and p["files"] != [] end)
      )

    assert length(notification(events, @updated, "stop")["files"]) <= 50
    assert call(pid, "fuzzyFileSearch/sessionStop", %{"sessionId" => "stop"}) == %{}

    assert missing(pid, "stop") == %{
             "code" => -32_600,
             "message" => "fuzzy file search session not found: stop"
           }

    assert_quiet(pid, "stop")

    for id <- ["stop", "never-started"],
        do: assert(call(pid, "fuzzyFileSearch/sessionStop", %{"sessionId" => id}) == %{})

    assert_ready(pid)
  end

  test "native session and malformed-input errors retain exact wire boundaries", ctx do
    pid = start(ctx)

    assert missing(pid, "unknown") == %{
             "code" => -32_600,
             "message" => "fuzzy file search session not found: unknown"
           }

    assert upstream_error(pid, "fuzzyFileSearch/sessionStart", %{
             "sessionId" => "",
             "roots" => [ctx.workspace]
           }) == %{"code" => -32_600, "message" => "sessionId must not be empty"}

    assert upstream_error(pid, "fuzzyFileSearch/sessionStart", %{
             "sessionId" => "empty",
             "roots" => []
           }) == %{
             "code" => -32_603,
             "message" =>
               "failed to start fuzzy file search session: at least one search directory is required"
           }

    assert missing(pid, "empty")["code"] == -32_600

    for {method, params} <- [
          {"fuzzyFileSearch", %{"query" => 42, "roots" => [ctx.workspace]}},
          {"fuzzyFileSearch", %{"query" => "x", "roots" => "invalid"}},
          {"fuzzyFileSearch", %{"roots" => []}},
          {"fuzzyFileSearch/sessionStart", %{"sessionId" => 42, "roots" => []}},
          {"fuzzyFileSearch/sessionUpdate", %{"sessionId" => "unknown", "query" => nil}},
          {"fuzzyFileSearch/sessionStop", %{}}
        ] do
      assert {:error, %Error{}} = Session.request(pid, method, params)
      error = upstream_error(pid, method, params, validation: :wire)
      assert error["code"] == -32_600
      assert String.starts_with?(error["message"], "Invalid request: ")
    end

    assert_ready(pid)
  end

  test "stable search works while unnegotiated experimental sessions fail locally and natively",
       ctx do
    write(ctx.workspace, "needle.txt")

    for negotiation <- [:absent, false] do
      pid = start(ctx, negotiation)
      assert [%{"path" => "needle.txt"}] = search(pid, "needle", [ctx.workspace])

      for {method, params} <- [
            {"fuzzyFileSearch/sessionStart",
             %{"sessionId" => "gated", "roots" => [ctx.workspace]}},
            {"fuzzyFileSearch/sessionUpdate", %{"sessionId" => "gated", "query" => "needle"}},
            {"fuzzyFileSearch/sessionStop", %{"sessionId" => "gated"}}
          ] do
        assert {:error, %Error{code: :experimental_api_required}} =
                 Session.request(pid, method, params)

        assert upstream_error(pid, method, params, validation: :wire) == %{
                 "code" => -32_600,
                 "message" => "#{method} requires experimentalApi capability"
               }
      end

      assert_ready(pid)
      assert :ok = Session.close(pid)
    end
  end

  defp start(ctx, negotiation \\ true) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: ctx.binary,
             args:
               SamgitaCodexDriver.NativeLaunchFixture.ordinary_args([
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: ctx.workspace,
             env: %{
               "HOME" => Path.join(ctx.root, "home"),
               "CODEX_HOME" => Path.join(ctx.root, "codex"),
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)
    capabilities = if negotiation == :absent, do: %{}, else: %{"experimentalApi" => negotiation}

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_fuzzy_fixture", "version" => "0.1.0"},
               capabilities
             )

    pid
  end

  defp write(root, path, body \\ "synthetic fuzzy fixture") do
    path = Path.join(root, path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, body)
  end

  defp result(root, path, type, name, score, indices),
    do: %{
      "root" => root,
      "path" => path,
      "match_type" => type,
      "file_name" => name,
      "score" => score,
      "indices" => indices
    }

  defp search(pid, query, roots),
    do: call(pid, "fuzzyFileSearch", %{"query" => query, "roots" => roots})["files"]

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp upstream_error(pid, method, params, opts \\ []) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             Session.request(pid, method, params, opts)

    error
  end

  defp missing(pid, id),
    do: upstream_error(pid, "fuzzyFileSearch/sessionUpdate", %{"sessionId" => id, "query" => "x"})

  defp begin_session(pid, id, roots) do
    assert call(pid, "fuzzyFileSearch/sessionStart", %{"sessionId" => id, "roots" => roots}) ==
             %{}

    # Drain the initial idle completion before attributing a completion to a query edit.
    await(pid, &notification(&1, @completed, id))
  end

  defp query(pid, id, query, predicate) do
    assert call(pid, "fuzzyFileSearch/sessionUpdate", %{"sessionId" => id, "query" => query}) ==
             %{}

    matches = fn events ->
      notification(events, @updated, id, &(&1["query"] == query and predicate.(&1["files"])))
    end

    events = await(pid, fn events -> matches.(events) && notification(events, @completed, id) end)
    assert notification(events, @completed, id) == %{"sessionId" => id}
    matches.(events)["files"]
  end

  defp notification(events, method, id, predicate \\ fn _ -> true end) do
    Enum.find_value(events, fn event ->
      params = event.wire["params"]

      if event.wire["method"] == method and params["sessionId"] == id and predicate.(params),
        do: params
    end)
  end

  defp await(pid, predicate),
    do: await(pid, predicate, [], System.monotonic_time(:millisecond) + 10_000)

  defp await(pid, predicate, acc, deadline) do
    assert {:ok, events} = Session.drain(pid)
    acc = acc ++ events

    cond do
      predicate.(acc) ->
        acc

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("Native fuzzy deadline: #{inspect(acc)}")

      true ->
        assert_ready(pid)

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, gap}} -> flunk("Native fuzzy gap: #{inspect(gap)}")
        after
          10 -> :ok
        end

        await(pid, predicate, acc, deadline)
    end
  end

  defp assert_quiet(pid, id) do
    # Match the pinned upstream suite: allow already-spawned notifications 250 ms,
    # then observe a separate 500 ms window. Neither stage establishes an absolute fence.
    observe(pid, id, System.monotonic_time(:millisecond) + 250, false)
    observe(pid, id, System.monotonic_time(:millisecond) + 500, true)
  end

  defp observe(pid, id, deadline, reject?) do
    assert {:ok, events} = Session.drain(pid)

    if reject? do
      refute notification(events, @updated, id)
      refute notification(events, @completed, id)
    end

    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0 do
      receive do
        {:codex_driver, ^pid, :events_available} ->
          :ok

        {:codex_driver, ^pid, {:gap, gap}} ->
          flunk("Native fuzzy observation gap: #{inspect(gap)}")
      after
        min(remaining, 10) -> :ok
      end

      observe(pid, id, deadline, reject?)
    end
  end

  defp assert_ready(pid),
    do: assert(%{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid))
end
