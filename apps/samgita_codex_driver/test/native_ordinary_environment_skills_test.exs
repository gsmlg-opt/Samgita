defmodule SamgitaCodexDriver.NativeOrdinaryEnvironmentSkillsTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.Schema

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_environment_skills_fixture.py", __DIR__)
  @script_sha "551c9397ec1755b96b1179e82ca621f4f10019f16b1e64c56c9d9a2306910711"
  @base Path.expand("../../../scripts/codex/ordinary_environment_connection_fixture.py", __DIR__)
  @base_sha "239f96ea487ae43eac710a9ddf40e7240abd462bcdc3cfb511552a48108d087c"
  @schema Path.expand(
            "../../samgita_protocol_codex/priv/upstream/0.163.0/experimental/v2/EnvironmentAddParams.json",
            __DIR__
          )
  @schema_sha "0ae0f9528196ee34205ac3003306924d57ec9cc77b05ce1ce7b4966b6187a106"
  @client_schema Path.expand(
                   "../../samgita_protocol_codex/priv/upstream/0.163.0/experimental/ClientRequest.json",
                   __DIR__
                 )
  @client_schema_sha "92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352"
  # Canonical bytes for these eight physical ClientRequest owners only.
  @root_owners [
    {83,
     """
     {
       "description": "A path owned by an execution environment.",
       "properties": {
         "environmentId": {
           "type": "string"
         },
         "path": {
           "description": "Absolute path for the root in the selected environment.",
           "type": "string"
         },
         "type": {
           "enum": [
             "environment"
           ],
           "title": "EnvironmentCapabilityRootLocationType",
           "type": "string"
         }
       },
       "required": [
         "environmentId",
         "path",
         "type"
       ],
       "title": "EnvironmentCapabilityRootLocation",
       "type": "object"
     }
     """, "6d73175de0ff8b0ea33a659b85a83a5cb0e02fa284fc73ce5bb6fdc6d1c54bbc"},
    {84,
     """
     {
       "type": "string"
     }
     """, "bf0b727f7b1c6d07c7312c6c7760fd34302744385611a86804210c77d80b0cc7"},
    {85,
     """
     {
       "description": "Absolute path for the root in the selected environment.",
       "type": "string"
     }
     """, "d9ab7109a0d12e8c918615fe790533fac5d91c75b22c03c0a852e53dc7b55444"},
    {86,
     """
     {
       "enum": [
         "environment"
       ],
       "title": "EnvironmentCapabilityRootLocationType",
       "type": "string"
     }
     """, "49e97242051a6bd025e35fa63dc26bbbcbd5d50f175dcd0c92729feda304d904"},
    {87,
     """
     "environment"
     """, "53aefa4c0496abfbe1b2195fcfe6b014f50b8c60dc9107d9d4cf52ae2dfb6fe3"},
    {592,
     """
     {
       "description": "Stable identifier supplied by the capability selection platform.",
       "type": "string"
     }
     """, "d05a3ee48c8c1c21a0dddd016971baad40071399e0fa24bac552ef977b72db70"},
    {593,
     """
     {
       "allOf": [
         {
           "$ref": "#/definitions/CapabilityRootLocation"
         }
       ],
       "description": "Where the selected root can be resolved."
     }
     """, "d954911f54bed7c433792f6f815dad8569d27f50214bace6bf2bd83078abd88c"},
    {594,
     """
     {
       "$ref": "#/definitions/CapabilityRootLocation"
     }
     """, "b23ca60674da2def8c170b28de596ac7f49045f72fa5865793cb7c3db8b30716"}
  ]
  @environment "owned-ordinary-skills-λ"
  @required %{"required" => ["owned:review"]}
  @prompts [
    "Owned ordinary environment skills first input",
    "Owned ordinary environment skills replacement input"
  ]
  @answers ["Owned ordinary first assistant λ", "Owned ordinary replacement assistant β"]

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert digest(binary) === @binary_sha
    assert digest(@script) === @script_sha
    assert digest(@base) === @base_sha
    assert digest(@schema) === @schema_sha
    assert digest(@client_schema) === @client_schema_sha
    python = System.find_executable("python3")
    assert is_binary(python), "BLOCKED_ENV: python3 required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-ordinary-skills-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    for name <- ~w(home app tmp), do: File.mkdir!(Path.join(root, name))
    %{root: root, binary: Path.expand(binary), python: python}
  end

  test "required executor skill is available before inference and explicit null clears it for a fresh thread",
       ctx do
    {pid, connection} = start(ctx)
    [started] = entries(ctx, "native_started")

    for process <- [started["pid"], started["executorPid"]],
        do: assert(digest("/proc/#{process}/exe") === @binary_sha)

    assert call(pid, "server/diagnostics", %{})["process"]["id"] === started["pid"]

    add(ctx, pid, 3899, @required)
    ready(ctx, pid)
    first = thread(ctx, pid, "owned-full-root", 3900)
    events1 = turn(pid, first, Enum.at(@prompts, 0), Enum.at(@answers, 0))
    assert_discovery(ctx, "owned-full-root", true)
    assert_provider(ctx, 1)

    add(ctx, pid, "3899", nil)
    ready(ctx, pid)
    second = thread(ctx, pid, "owned-empty-root", "3900")
    refute second === first
    events2 = turn(pid, second, Enum.at(@prompts, 1), Enum.at(@answers, 1))
    assert_discovery(ctx, "owned-empty-root", false)
    assert_provider(ctx, 2)

    assert [
             %{"id" => 3899, "skills" => @required} = registration1,
             %{"id" => "3899", "skills" => nil} = registration2
           ] = entries(ctx, "registration")

    for registration <- [registration1, registration2] do
      assert registration["method"] === "environment/add"
      assert registration["environmentId"] === @environment

      assert Enum.sort(Map.keys(Map.drop(registration, ~w(captureId monoNs wallMs event)))) ===
               ~w(environmentId id method skills)
    end

    for id <- [3899, "3899"] do
      assert length(Enum.filter(entries(ctx, "native_input"), &(&1["id"] === id))) === 1
      assert length(Enum.filter(entries(ctx, "native_output"), &(&1["id"] === id))) === 1
    end

    assert length(Enum.filter(entries(ctx, "native_input"), &(&1["method"] === "thread/start"))) ===
             2

    assert length(Enum.filter(entries(ctx, "native_input"), &(&1["method"] === "turn/start"))) ===
             2

    assert length(entries(ctx, "provider_response")) === 2
    assert_thread_capture_inventory(ctx)
    assert entries(ctx, "fixture_error") === []

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
    refute Enum.any?(events1 ++ events2, &(&1.kind === :server_request))
    assert_files(ctx)
    close(ctx, pid, connection)
    assert_files(ctx)
  end

  # This adapter injects connection bootstrap internally; only the actual skills
  # variant is claimed, never a credential-bearing complete request envelope.
  defp add(ctx, pid, id, skills) do
    document = @schema |> File.read!() |> JSON.decode!()
    index = if is_nil(skills), do: 1, else: 0
    selected = document["properties"]["skills"]["anyOf"] |> Enum.at(index)
    selected = Map.put(selected, "definitions", document["definitions"])
    assert :ok = Schema.validate(selected, skills, max_depth: 8)
    endpoint = ctx.root |> Path.join("endpoint.json") |> File.read!() |> JSON.decode!()

    params = %{
      "environmentId" => @environment,
      "execServerUrl" => endpoint["execServerUrl"],
      "skills" => skills
    }

    assert :ok = Schema.validate(document, params, max_depth: 8)
    assert call(pid, "environment/add", params, id) === %{}
  end

  defp ready(ctx, pid) do
    info = call(pid, "environment/info", %{"environmentId" => @environment})
    assert info["cwd"] === uri(ctx, "executor-workspace")

    assert call(pid, "environment/status", %{"environmentId" => @environment}) === %{
             "status" => "ready"
           }
  end

  defp thread(ctx, pid, root, request_id) do
    params = %{
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "cwd" => Path.join(ctx.root, "workspace"),
      "ephemeral" => false,
      "config" => %{"features.plugins" => true, "features.cwd_relative_turn_diffs" => true},
      "environments" => [
        %{"environmentId" => @environment, "cwd" => Path.join(ctx.root, "executor-workspace")}
      ],
      "selectedCapabilityRoots" => [
        %{
          "id" => "owned-skills-root",
          "location" => %{
            "type" => "environment",
            "environmentId" => @environment,
            "path" => uri(ctx, root)
          }
        }
      ]
    }

    request = %{"id" => request_id, "method" => "thread/start", "params" => params}

    assert {:ok, %{"id" => ^request_id, "result" => result} = response} =
             Session.request_native(pid, request, timeout_ms: 15_000)

    assert_thread_input(ctx, request, response, root)
    assert result["thread"]["turns"] === []
    id = result["thread"]["id"]
    assert is_binary(id) and id != ""
    id
  end

  defp assert_thread_input(ctx, request, response, root_name) do
    request_id = request["id"]
    assert [input] = Enum.filter(entries(ctx, "native_input"), &(&1["id"] === request_id))
    assert [output] = Enum.filter(entries(ctx, "native_output"), &(&1["id"] === request_id))
    assert input["method"] === "thread/start"
    assert output["method"] === nil

    driver = captured_jsonl(input["driverJsonlBase64"], 8_192)
    forwarded = captured_jsonl(input["nativeJsonlBase64"], 8_192)
    reply = captured_jsonl(output["nativeJsonlBase64"], 65_536)
    assert JSON.decode!(driver) === request
    assert JSON.decode!(forwarded) === request
    assert JSON.decode!(reply) === response

    document = @client_schema |> File.read!() |> JSON.decode!()
    variants = Map.fetch!(document, "oneOf")

    assert [selected] =
             Enum.filter(
               variants,
               &(get_in(&1, ["properties", "method", "enum"]) === ["thread/start"])
             )

    assert selected === Enum.at(variants, 7)
    assert selected["properties"]["params"] === %{"$ref" => "#/definitions/ThreadStartParams"}
    definitions = Map.fetch!(document, "definitions")
    params_node = Map.fetch!(definitions, "ThreadStartParams")
    roots_node = params_node["properties"]["selectedCapabilityRoots"]
    assert roots_node["items"] === %{"$ref" => "#/definitions/SelectedCapabilityRoot"}
    root_node = Map.fetch!(definitions, "SelectedCapabilityRoot")
    location_node = root_node["properties"]["location"]
    assert [location_ref] = location_node["allOf"]
    assert location_ref === %{"$ref" => "#/definitions/CapabilityRootLocation"}
    location_definition = Map.fetch!(definitions, "CapabilityRootLocation")

    assert [environment_node] =
             Enum.filter(
               location_definition["oneOf"],
               &(get_in(&1, ["properties", "type", "enum"]) === ["environment"])
             )

    assert environment_node === Enum.at(location_definition["oneOf"], 0)
    assert [captured_root] = JSON.decode!(forwarded)["params"]["selectedCapabilityRoots"]

    assert captured_root === %{
             "id" => "owned-skills-root",
             "location" => %{
               "environmentId" => @environment,
               "path" => uri(ctx, root_name),
               "type" => "environment"
             }
           }

    location = captured_root["location"]

    nodes = [
      {83, environment_node, location},
      {84, environment_node["properties"]["environmentId"], location["environmentId"]},
      {85, environment_node["properties"]["path"], location["path"]},
      {86, environment_node["properties"]["type"], location["type"]},
      {87, Enum.at(environment_node["properties"]["type"]["enum"], 0), location["type"]},
      {592, root_node["properties"]["id"], captured_root["id"]},
      {593, location_node, location},
      {594, location_ref, location}
    ]

    assert Enum.map(nodes, &elem(&1, 0)) === Enum.map(@root_owners, &elem(&1, 0))

    for {{index, node, value}, {owner_index, canonical, sha}} <- Enum.zip(nodes, @root_owners) do
      assert owner_index === index
      assert JSON.decode!(canonical) === node
      assert hash(canonical) === sha

      if index === 87 do
        assert value === node
      else
        assert :ok =
                 Schema.validate(Map.put(node, "definitions", definitions), value, max_depth: 32)
      end
    end

    for raw <- [driver, forwarded] do
      actual = JSON.decode!(raw)

      assert :ok =
               Schema.validate(Map.put(selected, "definitions", definitions), actual,
                 max_depth: 32
               )

      assert :ok = Schema.validate(document, actual, max_depth: 32)
    end
  end

  defp assert_thread_capture_inventory(ctx) do
    inputs = entries(ctx, "native_input")
    outputs = entries(ctx, "native_output")
    captured_inputs = Enum.filter(inputs, &Map.has_key?(&1, "driverJsonlBase64"))
    captured_outputs = Enum.filter(outputs, &Map.has_key?(&1, "nativeJsonlBase64"))
    assert Enum.map(captured_inputs, & &1["id"]) === [3900, "3900"]
    assert Enum.map(captured_outputs, & &1["id"]) === [3900, "3900"]

    for input <- inputs do
      if input["method"] === "thread/start" do
        assert Map.has_key?(input, "driverJsonlBase64")
        assert Map.has_key?(input, "nativeJsonlBase64")
      else
        refute Map.has_key?(input, "driverJsonlBase64")
        refute Map.has_key?(input, "nativeJsonlBase64")
      end
    end

    for output <- outputs do
      refute Map.has_key?(output, "driverJsonlBase64")

      if output["id"] in [3900, "3900"] do
        assert Map.has_key?(output, "nativeJsonlBase64")
      else
        refute Map.has_key?(output, "nativeJsonlBase64")
      end
    end

    raw_bytes =
      Enum.reduce(captured_inputs, 0, fn entry, size ->
        size + byte_size(captured_jsonl(entry["driverJsonlBase64"], 8_192)) +
          byte_size(captured_jsonl(entry["nativeJsonlBase64"], 8_192))
      end) +
        Enum.reduce(captured_outputs, 0, fn entry, size ->
          size + byte_size(captured_jsonl(entry["nativeJsonlBase64"], 65_536))
        end)

    assert raw_bytes <= 196_608
  end

  defp captured_jsonl(encoded, maximum) do
    assert is_binary(encoded)
    assert byte_size(encoded) <= 4 * div(maximum + 2, 3)
    raw = Base.decode64!(encoded)
    assert byte_size(raw) > 1 and byte_size(raw) <= maximum
    assert Base.encode64(raw) === encoded
    assert String.ends_with?(raw, "\n")
    assert length(String.split(raw, "\n", trim: true)) === 1
    raw
  end

  defp turn(pid, thread, prompt, answer) do
    result =
      call(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => prompt}]
      })

    turn = result["turn"]["id"]
    assert is_binary(turn) and turn != ""
    events = collect(pid, turn, [], now() + 10_000)

    for method <- ~w(turn/started turn/completed) do
      assert [notice] = notices(events, method)
      assert notice["threadId"] === thread and notice["turn"]["id"] === turn
    end

    assert [completed] = notices(events, "turn/completed")
    assert completed["turn"]["status"] === "completed"
    assert completed["turn"]["error"] === nil
    assert notices(events, "error") === []

    assert [message] =
             Enum.filter(
               notices(events, "item/completed"),
               &(&1["item"]["type"] === "agentMessage")
             )

    assert message["threadId"] === thread and message["turnId"] === turn
    assert message["item"]["text"] === answer
    events
  end

  defp assert_discovery(ctx, name, populated) do
    root = uri(ctx, name)
    entries = entries(ctx, "discovery")
    assert Enum.any?(entries, &(&1["method"] === "fs/walk" and &1["path"] === root))

    if populated do
      assert Enum.any?(
               entries,
               &(&1["method"] === "fs/readFile" and
                   &1["path"] === root <> "/.codex-plugin/plugin.json")
             )
    end

    skill =
      Enum.any?(
        entries,
        &(&1["method"] === "fs/readFile" and &1["path"] === root <> "/review/SKILL.md")
      )

    assert skill === populated
  end

  defp assert_provider(ctx, count) do
    rows = entries(ctx, "provider_request")
    assert length(rows) === count

    Enum.with_index(rows, 1)
    |> Enum.each(fn {row, index} ->
      assert row["sequence"] === index
      assert row["model"] === "mock-model"
      assert row["toolInput"] === false
      texts = row["texts"]
      assert Enum.count(texts, &(&1 === Enum.at(@prompts, index - 1))) === 1
      joined = Enum.join(texts, "\n")

      if index === 1 do
        assert joined =~ "owned:review"
        assert joined =~ "Owned ordinary review metadata λ."
      else
        refute joined =~ "owned:review"
        refute joined =~ "Owned ordinary review metadata λ."
        refute Enum.at(@prompts, 0) in texts
      end
    end)
  end

  defp assert_files(ctx) do
    assert digest(@script) === @script_sha
    assert digest(@base) === @base_sha
    assert digest(@schema) === @schema_sha
    assert digest(@client_schema) === @client_schema_sha
    assert [ready] = entries(ctx, "fixture_ready")
    for {path, sha} <- ready["snapshots"], do: assert(digest(path) === sha)
    assert File.ls!(Path.join(ctx.root, "owned-empty-root")) === [".codex-plugin"]
  end

  defp start(ctx) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 128,
               max_event_bytes: 1_048_576,
               transport:
                 {SamgitaCodexDriver.Transport.Stdio,
                  [
                    executable: ctx.python,
                    args: ["-u", @script, "--root", ctx.root, "--codex", ctx.binary],
                    cwd: ctx.root,
                    inherit_env: [],
                    max_message_bytes: 65_536,
                    env: %{
                      "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
                      "PYTHONDONTWRITEBYTECODE" => "1",
                      "HOME" => Path.join(ctx.root, "home"),
                      "CODEX_HOME" => Path.join(ctx.root, "app"),
                      "TMPDIR" => Path.join(ctx.root, "tmp")
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)

    on_exit(fn ->
      try do
        ensure_closed(ctx)
      after
        StdioSessionFixture.close(pid, connection)
      end

      assert_closed(ctx)
      assert Port.info(connection.port) === nil
      assert :atomics.get(connection.owner.completion, 1) === 1
      File.rm_rf!(ctx.root)
    end)

    await(fn -> length(entries(ctx, "native_started")) === 1 end, now() + 10_000)

    assert {:ok, %{"result" => _}} =
             Session.initialize(
               pid,
               %{"name" => "owned_ordinary_environment_skills", "version" => "1"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    {pid, connection}
  end

  defp call(pid, method, params, id \\ nil) do
    id = id || "ordinary-skills-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(
               pid,
               %{"id" => id, "method" => method, "params" => params},
               timeout_ms: 15_000
             )

    result
  end

  defp collect(pid, turn, events, deadline) do
    assert now() < deadline, "ordinary skills native completion deadline"
    assert {:ok, batch} = Session.drain(pid, 128)
    all = events ++ batch
    assert length(all) <= 128

    if Enum.any?(notices(all, "turn/completed"), &(&1["turn"]["id"] === turn)) do
      all
    else
      Process.sleep(10)
      collect(pid, turn, all, deadline)
    end
  end

  defp notices(events, method),
    do: for(event <- events, event.wire["method"] === method, do: event.wire["params"])

  defp entries(ctx, event) do
    path = Path.join(ctx.root, "journal.json")

    if File.exists?(path) do
      assert File.stat!(path).size <= 1_048_576
      rows = JSON.decode!(File.read!(path))["events"]
      assert length(rows) <= 160
      Enum.filter(rows, &(&1["event"] === event))
    else
      []
    end
  end

  defp ensure_closed(ctx) do
    if entries(ctx, "owner_closed") === [] do
      control = %{"id" => "ordinary-skills-close", "sequence" => 1, "action" => "close"}
      pending = Path.join(ctx.root, "control.pending")
      File.write!(pending, JSON.encode!(control))
      File.rename!(pending, Path.join(ctx.root, "control.json"))
      await(fn -> length(entries(ctx, "owner_closed")) === 1 end, now() + 10_000)
    end
  end

  defp close(ctx, pid, connection) do
    ensure_closed(ctx)
    StdioSessionFixture.close(pid, connection)
    assert_closed(ctx)
    assert Port.info(connection.port) === nil
    assert :atomics.get(connection.owner.completion, 1) === 1
  end

  defp assert_closed(ctx) do
    assert [%{"failed" => false}] =
             Enum.map(entries(ctx, "owner_closed"), &Map.take(&1, ["failed"]))

    assert [
             %{
               "childrenReaped" => true,
               "liveWorkers" => 0,
               "liveSockets" => 0,
               "providerRequests" => 2
             }
           ] =
             Enum.map(
               entries(ctx, "resources_closed"),
               &Map.take(&1, ~w(childrenReaped liveWorkers liveSockets providerRequests))
             )

    [started] = entries(ctx, "native_started")

    for field <- ~w(pid executorPid controllerPid) do
      await(fn -> not File.exists?("/proc/#{started[field]}") end, now() + 5_000)
    end

    assert entries(ctx, "fixture_error") === []
  end

  defp await(predicate, deadline) do
    if predicate.() do
      :ok
    else
      assert now() < deadline, "ordinary skills bounded wait"
      Process.sleep(10)
      await(predicate, deadline)
    end
  end

  defp uri(ctx, relative), do: "file://" <> Path.join(ctx.root, relative)
  defp now, do: System.monotonic_time(:millisecond)
  defp digest(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
