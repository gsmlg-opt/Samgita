defmodule SamgitaCodexDriver.NativeEnvironmentSkillsProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  @moduletag :real_codex
  @moduletag :isolated_environment_skills
  @moduletag timeout: 90_000
  @script Path.expand("../../../scripts/codex/isolated_environment_skills_fixture.py", __DIR__)
  @sha256 "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @token "synthetic-isolated-executor-credential-canary"
  @available "skills-available"
  @missing "skills-missing"
  @answer "Owned required skill gate admitted this assistant-only response"
  @shared_sources %{
    "../../../scripts/codex/isolated_environment_fixture.py" =>
      "f2097b358d182d87e1cf8b8203527c62e1ee6be945db72027dfb97acb90408c7",
    "../../../scripts/codex/isolated_thread_environment_fixture.py" =>
      "a494ce9b4999bb89391f7f363a63a1038d00ad7172bb16e92692fb89504b4482",
    "../../../scripts/codex/model_fixture.py" =>
      "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  }

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert digest(binary) == @sha256
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-environment-skills-" <>
          Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    ctx = %{root: root, binary: Path.expand(binary)}

    on_exit(fn ->
      if File.exists?(Path.join(root, "isolated-environment-journal.json")) do
        for started <- events(ctx, "native_started"),
            key <- ~w(pid executor_pid controller_pid namespace_owner_pid),
            do: await(fn -> not File.exists?("/proc/#{started[key]}") end)

        assert length(events(ctx, "native_started")) == length(events(ctx, "native_closed"))
      end

      File.rm_rf!(root)
    end)

    assert_immutable(ctx)
    ctx
  end

  test "actual executor skill satisfies only its exact required name before inference", ctx do
    pid = start(ctx)
    add(ctx, pid, @available, "owned:review")
    add(ctx, pid, @missing, "owned:absent")
    assert json(ctx, "skills-requests.json") == []

    discovery_before = discovery_count(ctx)
    available = thread(ctx, pid, @available)
    positive = turn(pid, available, "Owned required skill available input")
    received = collect(pid, positive, ctx)
    assert notices(received, "error") == [], inspect(diagnostic(ctx, received))
    assert_lifecycle(received, available, positive, "completed")
    assert [completed] = notices(received, "turn/completed")
    assert completed["turn"]["error"] == nil

    assert [message] =
             for(
               params <- notices(received, "item/completed"),
               params["item"]["type"] == "agentMessage",
               do: params
             )

    assert message["threadId"] == available and message["turnId"] == positive
    assert message["item"]["text"] == @answer
    assert discovery_count(ctx) > discovery_before
    assert_discovery(ctx)
    assert [request] = json(ctx, "skills-requests.json")
    assert request["model"] == "mock-model"
    assert user_texts(request) |> Enum.count(&(&1 == "Owned required skill available input")) == 1

    refute Enum.any?(request["input"], fn item ->
             item["type"] in ~w(function_call function_call_output custom_tool_call custom_tool_call_output)
           end)

    assert [
             %{
               "event" => "skills_model_request",
               "thread_id" => ^available,
               "turn_id" => ^positive,
               "model" => "mock-model",
               "request_auth" => "none"
             }
           ] = events(ctx, "skills_model_request")

    discovery_before = discovery_count(ctx)
    missing = thread(ctx, pid, @missing)
    negative = turn(pid, missing, "Owned required skill missing input")
    rejected = collect(pid, negative, ctx)
    assert_lifecycle(rejected, missing, negative, "failed")

    expected =
      "Fatal error: Required skill \"owned:absent\" from environment \"skills-missing\" is unavailable"

    assert [failure] = notices(rejected, "error")
    assert failure["threadId"] == missing and failure["turnId"] == negative
    assert failure["willRetry"] == false
    assert failure["error"]["message"] == expected
    assert failure["error"]["codexErrorInfo"] == "other"
    assert [completion] = notices(rejected, "turn/completed")
    assert completion["turn"]["error"]["message"] == expected
    assert completion["turn"]["error"]["codexErrorInfo"] == "other"

    refute Enum.any?(notices(rejected, "item/completed"), &(&1["item"]["type"] == "agentMessage"))
    assert discovery_count(ctx) > discovery_before
    assert json(ctx, "skills-requests.json") == [request]
    assert length(events(ctx, "skills_model_request")) == 1

    assert events(ctx, "skills_model_response") == [
             %{"event" => "skills_model_response", "count" => 1}
           ]

    assert json(ctx, "skills-provider-errors.json") == []

    loaded = call(pid, "thread/loaded/list", %{})
    assert Enum.sort(loaded["data"]) == Enum.sort([available, missing])
    assert loaded["nextCursor"] == nil

    assert Enum.count(events(ctx, "native_input"), &(&1["method"] == "environment/add")) == 2
    assert Enum.count(events(ctx, "native_input"), &(&1["method"] == "thread/start")) == 2
    assert Enum.count(events(ctx, "native_input"), &(&1["method"] == "turn/start")) == 2

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    assert_isolation(ctx)
    assert_immutable(ctx)
    assert :ok = Session.close(pid)
    await(fn -> length(events(ctx, "native_closed")) == 1 end)

    assert [
             %{
               "event" => "skills_resources_closed",
               "files_unchanged" => true,
               "provider_workers_stopped" => true,
               "model_requests" => 1
             }
           ] = events(ctx, "skills_resources_closed")

    assert [%{"children_reaped" => true, "workers_stopped" => true, "redaction_checked" => true}] =
             events(ctx, "resources_closed")

    for started <- events(ctx, "native_started"),
        key <- ~w(pid executor_pid controller_pid namespace_owner_pid),
        do: refute(File.exists?("/proc/#{started[key]}"))

    for name <- ~w(app executor) do
      data = File.read!(Path.join(ctx.root, "#{name}-stderr.log"))
      assert byte_size(data) <= 262_144
      refute data =~ @token
    end

    refute File.read!(Path.join(ctx.root, "isolated-environment-journal.json")) =~ @token
    assert json(ctx, "skills-provider-errors.json") == []
    assert_immutable(ctx)
  end

  defp start(ctx) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: System.find_executable("python3"),
             args: [@script, "--codex", ctx.binary, "--root", ctx.root],
             inherit_env: [],
             cwd: ctx.root,
             env: %{
               "HOME" => ctx.root,
               "CODEX_HOME" => Path.join(ctx.root, "app"),
               "TMPDIR" => ctx.root,
               "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
               "PYTHONDONTWRITEBYTECODE" => "1"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_owned_environment_skills", "version" => "1"},
               %{"experimentalApi" => true}
             )

    await(fn -> length(events(ctx, "native_started")) == 1 end)
    pid
  end

  defp add(ctx, pid, environment, required) do
    [started] = events(ctx, "native_started")

    assert call(pid, "environment/add", %{
             "environmentId" => environment,
             "execServerUrl" => started["executor_url"],
             "authBearerToken" => @token,
             "connectTimeoutMs" => 15_000,
             "skills" => %{"required" => [required]}
           }) == %{}

    assert call(pid, "environment/info", %{"environmentId" => environment})["cwd"] ==
             "file://" <> Path.join(ctx.root, "executor-workspace")
  end

  defp thread(ctx, pid, environment) do
    params = %{
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "cwd" => Path.join(ctx.root, "workspace"),
      "sandbox" => "read-only",
      "approvalPolicy" => "on-request",
      "ephemeral" => false,
      "config" => %{
        "features.plugins" => true,
        "features.cwd_relative_turn_diffs" => true
      },
      "environments" => [
        %{"environmentId" => environment, "cwd" => Path.join(ctx.root, "executor-workspace")}
      ],
      "selectedCapabilityRoots" => [
        %{
          "id" => "owned-skills-root",
          "location" => %{
            "type" => "environment",
            "environmentId" => environment,
            "path" => "file://" <> Path.join(ctx.root, "owned-capability-root")
          }
        }
      ]
    }

    result = call(pid, "thread/start", params)
    assert result["thread"]["turns"] == []
    result["thread"]["id"]
  end

  defp turn(pid, thread, text),
    do:
      call(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => text}]
      })["turn"]["id"]

  defp assert_lifecycle(events, thread, turn, status) do
    for method <- ~w(turn/started turn/completed) do
      assert [notice] = notices(events, method)
      assert notice["threadId"] == thread and notice["turn"]["id"] == turn
    end

    assert [completion] = notices(events, "turn/completed")
    assert completion["turn"]["status"] == status
    refute Enum.any?(events, &(&1.kind == :server_request))
  end

  defp assert_discovery(ctx) do
    root = "file://" <> Path.join(ctx.root, "owned-capability-root")
    rpcs = events(ctx, "exec_rpc")
    assert Enum.any?(rpcs, &(&1["method"] == "fs/walk" and &1["path"] == root))

    for path <- [root <> "/.codex-plugin/plugin.json", root <> "/review/SKILL.md"],
        do: assert(Enum.any?(rpcs, &(&1["method"] == "fs/readFile" and &1["path"] == path)))

    assert Enum.all?(
             rpcs,
             &(&1["method"] in ~w(initialize initialized environment/info environment/status fs/walk fs/getMetadata fs/readFile environmentConfig/read))
           )
  end

  defp assert_isolation(ctx) do
    data = json(ctx, "isolated-environment-journal.json")
    assert data["namespace"]["parent"] != data["namespace"]["child"]
    assert data["namespace"]["parent_user"] != data["namespace"]["child_user"]
    assert data["namespace"]["interfaces"] == ["lo"]
    refute data["namespace"]["default_route"] or data["namespace"]["ipv6_default_route"]

    for event <- ~w(fixture_error forbidden_exec_rpc unexpected_http),
        do: assert(events(ctx, event) == [])

    probes =
      for probe <- events(ctx, "native_auth_probe"), do: {probe["credential"], probe["status"]}

    assert probes == [{"absent", 401}, {"wrong", 401}, {"valid", 101}]
  end

  defp assert_immutable(ctx) do
    assert digest(ctx.binary) == @sha256

    for {relative, expected} <- @shared_sources,
        do: assert(digest(Path.expand(relative, __DIR__)) == expected)

    for ready <- events_if_started(ctx),
        {path, expected} <- ready["owned_files"],
        do: assert(digest(path) == expected)
  end

  defp events_if_started(ctx) do
    if File.exists?(Path.join(ctx.root, "isolated-environment-journal.json")),
      do: events(ctx, "skills_fixture_ready"),
      else: []
  end

  defp collect(pid, turn, ctx),
    do: collect(pid, turn, ctx, [], System.monotonic_time(:millisecond) + 10_000)

  defp collect(pid, turn, ctx, received, deadline) do
    assert {:ok, batch} = Session.drain(pid, 10_000)
    received = received ++ batch

    if Enum.any?(notices(received, "turn/completed"), &(&1["turn"]["id"] == turn)) do
      received
    else
      assert System.monotonic_time(:millisecond) < deadline,
             inspect(diagnostic(ctx, received))

      Process.sleep(10)
      collect(pid, turn, ctx, received, deadline)
    end
  end

  defp diagnostic(ctx, received) do
    %{
      errors: notices(received, "error"),
      fixture_errors: events(ctx, "fixture_error"),
      rpc_attempts: events(ctx, "skills_rpc_attempt"),
      provider_errors: json(ctx, "skills-provider-errors.json")
    }
  end

  defp call(pid, method, params) do
    id = "owned-environment-skills-#{System.unique_integer([:positive])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, method, params, id: id)

    result
  end

  defp notices(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp user_texts(request),
    do:
      for(
        item <- request["input"],
        item["role"] == "user",
        part <- item["content"],
        part["type"] == "input_text",
        do: part["text"]
      )

  defp discovery_count(ctx), do: Enum.count(events(ctx, "exec_rpc"), &(&1["method"] == "fs/walk"))
  defp digest(path), do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
  defp json(ctx, name), do: ctx.root |> Path.join(name) |> File.read!() |> JSON.decode!()

  defp events(ctx, name),
    do:
      Enum.filter(
        json(ctx, "isolated-environment-journal.json")["events"],
        &(&1["event"] == name)
      )

  defp await(predicate), do: await(predicate, System.monotonic_time(:millisecond) + 10_000)

  defp await(predicate, deadline) do
    if value = predicate.() do
      value
    else
      assert System.monotonic_time(:millisecond) < deadline, "owned required-skills deadline"
      Process.sleep(10)
      await(predicate, deadline)
    end
  end
end
