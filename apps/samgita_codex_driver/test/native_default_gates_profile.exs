defmodule SamgitaCodexDriver.DefaultGateRecordingUDS do
  @moduledoc false
  @behaviour SamgitaCodexDriver.Transport
  alias SamgitaCodexDriver.Transport.UnixSocket

  @impl true
  def open(opts) do
    with {:ok, inner} <- UnixSocket.open(opts),
         do: {:ok, %{inner: inner, sent: Keyword.fetch!(opts, :sent_path)}}
  end

  @impl true
  def send(state, json) do
    # Synthetic fixtures only. Record the exact bytes; do not normalize params.
    File.write!(state.sent, json <> "\n", [:append])

    case UnixSocket.send(state.inner, json) do
      {:ok, inner} -> {:ok, %{state | inner: inner}}
      {:error, error, inner} -> {:error, error, %{state | inner: inner}}
    end
  end

  @impl true
  def handle_info(message, state) do
    case UnixSocket.handle_info(message, state.inner) do
      :unknown -> :unknown
      {:ok, events, inner} -> {:ok, events, %{state | inner: inner}}
      {:error, error, inner} -> {:error, error, %{state | inner: inner}}
    end
  end

  @impl true
  def close(state), do: UnixSocket.close(state.inner)
  @impl true
  def metadata(state), do: UnixSocket.metadata(state.inner)
end

defmodule SamgitaCodexDriver.NativeDefaultGatesProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{DefaultGateRecordingUDS, Session}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag :isolated_default_gates
  @moduletag timeout: 90_000
  @script Path.expand("../../../scripts/codex/isolated_default_gates_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-default-gates-" <>
          Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)

    for directory <- ~w(home codex workspace tmp bin),
        do: File.mkdir!(Path.join(root, directory))

    File.cp!("/bin/sh", Path.join(root, "bin/sh"))
    File.write!(Path.join(root, "requests.json"), "[]")
    on_exit(fn -> File.rm_rf!(root) end)

    ctx = %{
      root: root,
      socket: Path.join(root, "native.sock"),
      workspace: Path.join(root, "workspace"),
      parent_netns: File.read_link!("/proc/self/ns/net"),
      parent_userns: File.read_link!("/proc/self/ns/user")
    }

    {:ok, owner} =
      Stdio.open(
        executable: System.find_executable("python3"),
        args: [@script, "--root", root, "--codex", Path.expand(binary)],
        cwd: ctx.workspace,
        inherit_env: [],
        env: %{
          "HOME" => Path.join(root, "home"),
          "CODEX_HOME" => Path.join(root, "codex"),
          "TMPDIR" => Path.join(root, "tmp"),
          "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
          "SHELL" => Path.join(root, "bin/sh"),
          "NO_COLOR" => "1",
          "RUST_LOG" => "off",
          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
          "PYTHONDONTWRITEBYTECODE" => "1"
        }
      )

    on_exit(fn ->
      assert :ok = Stdio.close(owner)

      if File.exists?(Path.join(root, "state.json")) do
        proof = read(ctx, "state.json")

        for pid <-
              proof["native_pids"] ++ [proof["controller_pid"], proof["namespace_owner_pid"]],
            do: await(fn -> not File.exists?("/proc/#{pid}") end, "owned process reaping")
      end
    end)

    await(
      fn ->
        File.exists?(Path.join(root, "state.json")) and read(ctx, "state.json")["ready"]
      end,
      "owned fixture readiness"
    )

    proof = read(ctx, "state.json")
    assert proof["ready"]
    assert proof["namespace"] != ctx.parent_netns
    assert proof["parent_namespace"] == ctx.parent_netns
    assert proof["user_namespace"] != ctx.parent_userns
    assert proof["parent_user_namespace"] == ctx.parent_userns
    assert proof["interfaces"] == ["lo"]
    refute proof["default_route"] or proof["ipv6_default_route"]
    ctx
  end

  test "primitive experimental booleans default false, reject null, and gate true", ctx do
    for negotiation <- [:absent, false] do
      {pid, journal} = client(ctx, negotiation)

      for field <- ~w(allowProviderModelFallback experimentalRawEvents) do
        for extra <- [%{}, %{field => false}] do
          result = start(pid, ctx, extra)
          assert result["model"] == "mock-model"
          assert last_params(journal, "thread/start") == params(ctx, extra)
        end

        reject_gate(pid, ctx, journal, field, true)
        before = count(journal, "thread/start")

        assert {:error, %Error{code: :schema_violation}} =
                 Session.request(pid, "thread/start", params(ctx, %{field => nil}))

        assert count(journal, "thread/start") == before
        error = wire_error(pid, "thread/start", params(ctx, %{field => nil}))
        assert error["code"] == -32_600
        assert error["message"] =~ "invalid type: null, expected a boolean"
      end
    end

    {enabled, journal} = client(ctx, true)

    for field <- ~w(allowProviderModelFallback experimentalRawEvents) do
      assert start(enabled, ctx, %{field => true})["model"] == "mock-model"
      assert last_params(journal, "thread/start")[field] == true
    end

    assert read(ctx, "requests.json") == []
  end

  test "optional false, empty vectors, and empty strings stay active experimental values", ctx do
    values = [
      {"daybreakEnabled", false},
      {"daybreakEnabled", true},
      {"dynamicTools", []},
      {"mockExperimentalField", ""},
      {"mockExperimentalField", "owned-default-value"},
      {"historyMode", "legacy"},
      {"historyMode", "paginated"}
    ]

    {stable, journal} = client(ctx, false)

    for field <- ~w(daybreakEnabled dynamicTools mockExperimentalField historyMode) do
      result = start(stable, ctx, %{field => nil})
      assert result["thread"]["daybreakEnabled"] == nil
      assert last_params(journal, "thread/start")[field] == nil
      assert Map.has_key?(last_params(journal, "thread/start"), field)
    end

    for {field, value} <- values, do: reject_gate(stable, ctx, journal, field, value)

    {enabled, enabled_journal} = client(ctx, true)

    for {field, value} <- values do
      result = start(enabled, ctx, %{field => value})
      assert last_params(enabled_journal, "thread/start") == params(ctx, %{field => value})
      if field in ~w(daybreakEnabled historyMode), do: assert(result["thread"][field] == value)
    end

    assert read(ctx, "requests.json") == []
  end

  test "thread tier double-option inherits config while explicit null requests native default",
       ctx do
    {pid, journal} = client(ctx, false)

    for {extra, expected} <- [
          {%{}, "flex"},
          {%{"serviceTier" => nil}, "default"},
          {%{"serviceTier" => "default"}, "default"},
          {%{"serviceTier" => "flex"}, "flex"},
          {%{"serviceTier" => "owned-unsupported-tier"}, nil}
        ] do
      result = start(pid, ctx, extra)
      assert result["serviceTier"] == expected
      assert last_params(journal, "thread/start") == params(ctx, extra)
      assert result["thread"]["ephemeral"] == false
    end

    assert read(ctx, "requests.json") == []
  end

  test "thread null options preserve durable defaults and explicit history/ephemeral choices",
       ctx do
    {pid, journal} = client(ctx, true)

    for {extra, ephemeral, history} <- [
          {%{}, false, "paginated"},
          {%{"ephemeral" => nil, "historyMode" => nil}, false, "paginated"},
          {%{"ephemeral" => false}, false, "paginated"},
          {%{"ephemeral" => true}, true, "paginated"},
          {%{"historyMode" => "legacy"}, false, "legacy"},
          {%{"historyMode" => "paginated"}, false, "paginated"}
        ] do
      result = start(pid, ctx, extra)
      assert result["thread"]["ephemeral"] == ephemeral
      assert result["thread"]["historyMode"] == history
      assert last_params(journal, "thread/start") == params(ctx, extra)
    end

    assert read(ctx, "requests.json") == []
  end

  test "turn optional maps accept null but gate empty objects without starting rejected turns",
       ctx do
    {stable, journal} = client(ctx, false)
    thread = start(stable, ctx)["thread"]["id"]

    for {field, index} <- Enum.with_index(~w(additionalContext responsesapiClientMetadata), 1) do
      for {extra, marker} <- [{%{}, index * 10}, {%{field => nil}, index * 10 + 1}] do
        before = length(read(ctx, "requests.json"))
        turn = start_turn(stable, thread, marker, extra)
        events = finish(stable, turn)
        assert length(read(ctx, "requests.json")) == before + 1
        assert last_params(journal, "turn/start") == turn_params(thread, marker, extra)
        refute Enum.any?(events, &(&1.kind == :server_request))
      end

      rejected = turn_params(thread, index * 10 + 2, %{field => %{}})
      requests = read(ctx, "requests.json")
      before = count(journal, "turn/start")

      assert {:error, %Error{code: :experimental_api_required}} =
               Session.request(stable, "turn/start", rejected)

      assert count(journal, "turn/start") == before

      assert wire_error(stable, "turn/start", rejected) == %{
               "code" => -32_600,
               "message" => "turn/start.#{field} requires experimentalApi capability"
             }

      assert read(ctx, "requests.json") == requests
      assert {:ok, events} = Session.drain(stable)
      refute Enum.any?(events, &(&1.wire["method"] == "turn/started"))
    end

    {enabled, enabled_journal} = client(ctx, true)
    thread = start(enabled, ctx)["thread"]["id"]

    for {field, index} <- Enum.with_index(~w(additionalContext responsesapiClientMetadata), 100) do
      turn = start_turn(enabled, thread, index, %{field => %{}})
      events = finish(enabled, turn)

      assert last_params(enabled_journal, "turn/start") ==
               turn_params(thread, index, %{field => %{}})

      refute Enum.any?(events, &(&1.kind == :server_request))
    end

    assert length(read(ctx, "requests.json")) == 6
  end

  defp client(ctx, negotiation) do
    name = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
    journal = Path.join(ctx.root, "sent-" <> name <> ".jsonl")
    File.write!(journal, "")

    {:ok, pid} =
      Session.start_link(
        transport: {DefaultGateRecordingUDS, [socket_path: ctx.socket, sent_path: journal]}
      )

    on_exit(fn ->
      if Process.alive?(pid) do
        try do
          assert :ok = Session.close(pid)
        catch
          :exit, {:noproc, _} -> :ok
        end
      end
    end)

    capabilities = if negotiation == :absent, do: %{}, else: %{"experimentalApi" => negotiation}

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_owned_defaults", "version" => "0.1.0"},
               capabilities
             )

    {pid, journal}
  end

  defp reject_gate(pid, ctx, journal, field, value) do
    loaded = call(pid, "thread/loaded/list", %{})["data"] |> Enum.sort()
    assert {:ok, _} = Session.drain(pid)
    before = count(journal, "thread/start")

    assert {:error, %Error{code: :experimental_api_required}} =
             Session.request(pid, "thread/start", params(ctx, %{field => value}))

    assert count(journal, "thread/start") == before

    assert wire_error(pid, "thread/start", params(ctx, %{field => value})) == %{
             "code" => -32_600,
             "message" => "thread/start.#{field} requires experimentalApi capability"
           }

    assert call(pid, "thread/loaded/list", %{})["data"] |> Enum.sort() == loaded
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.wire["method"] in ["thread/started", "turn/started"]))
  end

  defp params(ctx, extra),
    do:
      Map.merge(
        %{
          "cwd" => ctx.workspace,
          "model" => "mock-model",
          "modelProvider" => "fixture",
          "sandbox" => "read-only",
          "approvalPolicy" => "on-request"
        },
        extra
      )

  defp start(pid, ctx, extra \\ %{}), do: call(pid, "thread/start", params(ctx, extra))

  defp turn_params(thread, marker, extra),
    do:
      Map.merge(
        %{
          "threadId" => thread,
          "input" => [%{"type" => "text", "text" => "synthetic:defaults:#{marker}"}]
        },
        extra
      )

  defp start_turn(pid, thread, marker, extra),
    do: call(pid, "turn/start", turn_params(thread, marker, extra))["turn"]["id"]

  defp finish(pid, turn), do: finish(pid, turn, [], now() + 15_000)

  defp finish(pid, turn, acc, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    refute Enum.any?(incoming, &(&1.kind == :server_request)), "no tool or approval is authorized"
    acc = acc ++ incoming

    completed =
      Enum.find(
        acc,
        &(get_in(&1, [:wire, "method"]) == "turn/completed" and
            get_in(&1, [:wire, "params", "turn", "id"]) == turn)
      )

    if completed do
      assert completed.wire["params"]["turn"]["status"] == "completed"
      acc
    else
      assert now() < deadline, "owned assistant turn deadline"

      receive do
      after
        10 -> :ok
      end

      finish(pid, turn, acc, deadline)
    end
  end

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp wire_error(pid, method, params) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             Session.request(pid, method, params, validation: :wire)

    error
  end

  defp sent(path),
    do: path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)

  defp count(path, method), do: Enum.count(sent(path), &(&1["method"] == method))

  defp last_params(path, method),
    do:
      sent(path) |> Enum.filter(&(&1["method"] == method)) |> List.last() |> Map.fetch!("params")

  defp read(ctx, name), do: ctx.root |> Path.join(name) |> File.read!() |> JSON.decode!()
  defp now, do: System.monotonic_time(:millisecond)
  defp await(fun, label), do: await(fun, label, now() + 10_000)

  defp await(fun, label, deadline) do
    if fun.() do
      :ok
    else
      assert now() < deadline, label

      receive do
      after
        10 -> :ok
      end

      await(fun, label, deadline)
    end
  end
end
