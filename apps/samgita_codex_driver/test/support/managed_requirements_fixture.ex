defmodule SamgitaCodexDriver.ManagedRequirementsFixture do
  @moduledoc false
  import ExUnit.Assertions

  alias SamgitaCodexDriver.{Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  import TurnFixture, only: [call: 3]

  @script Path.expand("../../../../scripts/codex/managed_requirements_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

  def start(ctx, client_name) do
    parents = Map.new(~w(user mnt net), &{&1, File.read_link!("/proc/self/ns/" <> &1)})
    File.rm(Path.join(ctx.root, "startup-failure.json"))

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: System.find_executable("python3"),
             args: ["-I", @script, "--root", ctx.root, "--codex", ctx.binary],
             cwd: Path.join(ctx.root, "workspace"),
             inherit_env: [],
             env: %{
               "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
               "HOME" => Path.join(ctx.root, "home"),
               "CODEX_HOME" => Path.join(ctx.root, "codex"),
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PYTHONDONTWRITEBYTECODE" => "1"
             }
           ]}
      )

    # Register before initialization so every failure still closes owned resources.
    StdioSessionFixture.register_cleanup(pid)

    initialized =
      Session.initialize(pid, %{"name" => client_name, "version" => "0.1.0"}, %{
        "experimentalApi" => true
      })

    assert match?({:ok, %{"result" => _}}, initialized),
           "BLOCKED_ENV: managed policy startup #{inspect(initialized)} #{failure(ctx)}"

    proof = ctx.root |> Path.join("proof.json") |> File.read!() |> JSON.decode!()
    assert proof["parents"] == parents
    for name <- ~w(user mnt net), do: assert(proof["namespaces"][name] != parents[name])
    assert proof["requirements_path"] == "/etc/codex/requirements.toml"
    assert proof["project_root_marker"] == Path.join(ctx.root, "workspace/.git")
    assert proof["requirements_read_only"] and proof["private_etc_tmpfs"]
    assert proof["interfaces"] == ["lo"]
    refute proof["default_route"] or proof["ipv6_default_route"]
    assert proof["binary_sha256"] == @binary_sha
    pid
  end

  def close(ctx, pid) do
    proof = ctx.root |> Path.join("proof.json") |> File.read!() |> JSON.decode!()
    assert :ok = Session.close(pid)

    for key <- ~w(native_pid namespace_owner_pid),
        do: refute(File.exists?("/proc/#{proof[key]}"), "Owned policy process remains: #{key}")
  end

  def assert_idle(pid) do
    assert call(pid, "thread/loaded/list", %{})["data"] == []
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request))
    refute Enum.any?(events, &(&1.wire["method"] == "turn/started"))
    assert Session.status(pid).phase == :ready
    assert Session.status(pid).pending == 0
    assert Session.status(pid).interactions == 0
  end

  defp failure(ctx) do
    case File.read(Path.join(ctx.root, "startup-failure.json")) do
      {:ok, text} -> text
      {:error, :enoent} -> "No fixture startup failure recorded"
    end
  end
end
