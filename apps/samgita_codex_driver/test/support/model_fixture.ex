defmodule SamgitaCodexDriver.ModelFixture do
  @moduledoc false
  @script Path.expand("../../../../scripts/codex/model_fixture.py", __DIR__)

  def start(root, scenario) do
    home = Path.join(root, "home")
    codex_home = Path.join(root, "codex")
    workspace = Path.join(root, "workspace")
    bin = Path.join(root, "bin")
    requests = Path.join(root, "requests.json")
    Enum.each([home, codex_home, workspace, bin], &File.mkdir_p!/1)
    # Pinned Codex uses the model path to select a shell type, then searches PATH.
    # A private executable avoids host-specific symlink or login-shell selection.
    File.cp!("/bin/sh", Path.join(bin, "sh"))
    python = System.find_executable("python3") || raise "BLOCKED_ENV: Python 3 required"
    script = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT") || @script
    unless File.regular?(script), do: raise("BLOCKED_ENV: model-provider fixture script missing")

    port =
      Port.open({:spawn_executable, python}, [
        :binary,
        :exit_status,
        args: [
          script,
          "--codex-home",
          codex_home,
          "--workspace",
          workspace,
          "--scenario",
          scenario,
          "--requests-file",
          requests
        ]
      ])

    wait_startup(port, <<>>, %{
      port: port,
      home: home,
      codex_home: codex_home,
      workspace: workspace,
      bin: bin,
      requests: requests
    })
  end

  defp wait_startup(port, buffer, fixture) do
    receive do
      {^port, {:data, bytes}} ->
        buffer = buffer <> bytes

        case String.split(buffer, "\n", parts: 2) do
          [line, _rest] -> Map.put(fixture, :url, JSON.decode!(line)["url"])
          _ -> wait_startup(port, buffer, fixture)
        end

      {^port, {:exit_status, status}} ->
        raise "BLOCKED_ENV: fixture exited with #{status}"
    after
      5_000 ->
        close(fixture)
        raise "BLOCKED_ENV: fixture startup deadline"
    end
  end

  def close(%{port: port}) do
    if Port.info(port), do: Port.close(port)
    :ok
  rescue
    _ -> :ok
  end

  def requests(fixture) do
    fixture.requests |> File.read!() |> JSON.decode!()
  end
end
