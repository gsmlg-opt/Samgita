defmodule StandaloneCodex.ProviderFixture do
  @moduledoc """
  A disposable loopback model provider for the real Codex example.

  The Python script is an explicit example input; this helper has no dependency
  on the umbrella's configuration or test support. It never emulates app-server.
  """
  alias SamgitaCodexDriver.Transport.Stdio

  def with(root, script, fun) do
    unless File.regular?(script), do: raise("Model-provider fixture script is required")
    # Require a new directory: an example run must not overwrite existing data.
    File.mkdir_p!(Path.dirname(root))
    :ok = File.mkdir(root)
    home = Path.join(root, "home")
    codex_home = Path.join(root, "codex")
    workspace = Path.join(root, "workspace")
    bin = Path.join(home, "bin")
    requests = Path.join(root, "requests.json")
    Enum.each([home, codex_home, workspace, bin], &File.mkdir_p!/1)
    File.cp!("/bin/sh", Path.join(bin, "sh"))
    python = System.find_executable("python3") || raise "Python 3 is required"

    {:ok, transport} =
      Stdio.open(
        executable: python,
        env: %{"CODEX_HOME" => codex_home, "HOME" => home},
        args: [
          script,
          "--codex-home",
          codex_home,
          "--workspace",
          workspace,
          "--scenario",
          "dynamic_tool",
          "--requests-file",
          requests
        ]
      )

    fixture = %{
      port: transport.port,
      transport: transport,
      home: home,
      codex_home: codex_home,
      workspace: workspace,
      bin: bin,
      requests: requests
    }

    try do
      deadline = System.monotonic_time(:millisecond) + 5_000
      fun.(wait_startup(fixture, <<>>, deadline))
    after
      :ok = Stdio.close(transport)
    end
  end

  def requests(fixture) do
    case File.read(fixture.requests) do
      {:ok, bytes} -> JSON.decode!(bytes)
      {:error, :enoent} -> []
      {:error, reason} -> raise File.Error, reason: reason, action: "read", path: fixture.requests
    end
  end

  defp wait_startup(%{port: port} = fixture, buffer, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, bytes}} ->
        buffer = buffer <> bytes

        case String.split(buffer, "\n", parts: 2) do
          [line, _rest] -> Map.put(fixture, :url, JSON.decode!(line)["url"])
          _ -> wait_startup(fixture, buffer, deadline)
        end

      {^port, {:exit_status, status}} ->
        raise "Model-provider fixture exited with #{status}"
    after
      remaining -> raise "Model-provider fixture startup deadline"
    end
  end
end
