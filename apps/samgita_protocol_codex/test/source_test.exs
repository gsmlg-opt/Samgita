defmodule SamgitaProtocolCodex.SourceTest do
  use ExUnit.Case, async: true

  @root Path.expand("../priv/upstream/current", __DIR__)

  test "the snapshot records its release and every file matches its digest" do
    manifest = SamgitaProtocolCodex.source()
    assert manifest["tag"] == "rust-v" <> manifest["version"]
    assert manifest["commit"] =~ ~r/\A[0-9a-f]{40}\z/
    assert manifest["binary_version_output"] == "codex-cli " <> manifest["version"]

    files =
      @root
      |> Path.join("**")
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&Path.relative_to(&1, @root))
      |> Kernel.--(["source.json"])

    assert Enum.sort(files) == Enum.sort(Map.keys(manifest["files_sha256"]))

    for {path, sha} <- manifest["files_sha256"] do
      body = File.read!(Path.join(@root, path))
      assert sha(body) == sha, path

      if String.ends_with?(path, ".json"),
        do: assert(is_map(JSON.decode!(body)) or is_list(JSON.decode!(body)))
    end
  end

  test "the selected wire fixtures use actual pinned method parameter fields" do
    cases = [
      {"thread/start", %{}, "v2/ThreadStartParams.json"},
      {"thread/read", %{"thread_id" => "thr"}, "v2/ThreadReadParams.json"},
      {"thread/resume", %{"thread_id" => "thr"}, "v2/ThreadResumeParams.json"},
      {"turn/start", %{"thread_id" => "thr", "input" => [%{"type" => "text", "text" => "hello"}]},
       "v2/TurnStartParams.json"},
      {"turn/steer",
       %{
         "thread_id" => "thr",
         "turn_id" => "turn",
         "input" => [%{"type" => "text", "text" => "hello"}]
       }, "v2/TurnSteerParams.json"},
      {"turn/interrupt", %{"thread_id" => "thr", "turn_id" => "turn"},
       "v2/TurnInterruptParams.json"}
    ]

    for {method, params, source} <- cases do
      request = %{
        "schema_version" => "1.0",
        "type" => "request",
        "id" => "request",
        "correlation_id" => "correlation",
        "command_id" => "command",
        "method" => method,
        "params" => params
      }

      assert {:ok, wire} = SamgitaProtocolCodex.encode_request(request)
      schema = @root |> Path.join("stable/" <> source) |> File.read!() |> JSON.decode!()
      assert Enum.all?(Map.get(schema, "required", []), &Map.has_key?(wire["params"], &1))
      assert Enum.all?(Map.keys(wire["params"]), &Map.has_key?(schema["properties"], &1))
    end
  end

  defp sha(body), do: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
end
