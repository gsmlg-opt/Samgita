defmodule SamgitaProtocolCodex.SourceTest do
  use ExUnit.Case, async: true

  @root Path.expand("../priv/upstream", __DIR__)

  test "every vendored official reference matches its pinned upstream and local hash" do
    manifest = @root |> Path.join("source.json") |> File.read!() |> JSON.decode!()
    assert manifest["commit"] == "83086188ae0614bd882818ff1aa23f3194962012"
    assert manifest["release"] == "rust-v0.163.0"

    for {path, entry} <- manifest["files"] do
      body = File.read!(Path.join(@root, path))
      assert sha(body) == entry["vendored_sha256"], path

      original =
        if String.ends_with?(path, ".json"), do: String.trim_trailing(body, "\n"), else: body

      assert sha(original) == entry["upstream_sha256"], path
      if String.ends_with?(path, ".json"), do: assert(is_map(JSON.decode!(body)))
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
      schema = @root |> Path.join("schema/" <> source) |> File.read!() |> JSON.decode!()
      assert Enum.all?(Map.get(schema, "required", []), &Map.has_key?(wire["params"], &1))
      assert Enum.all?(Map.keys(wire["params"]), &Map.has_key?(schema["properties"], &1))
    end
  end

  defp sha(body), do: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
end
