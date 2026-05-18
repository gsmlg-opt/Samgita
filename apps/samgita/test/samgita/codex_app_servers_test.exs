defmodule Samgita.CodexAppServersTest do
  use Samgita.DataCase, async: false

  alias Samgita.CodexAppServers
  alias Samgita.Projects

  @valid_attrs %{name: "Codex Project", git_url: "git@github.com:test/codex.git"}

  setup do
    on_exit(fn ->
      Application.delete_env(:samgita_provider, :ssh_command)
    end)

    :ok
  end

  describe "configure/2" do
    test "stores local launch config and working path" do
      project = create_project()
      repo_path = make_git_dir()

      assert {:ok, updated} =
               CodexAppServers.configure(project, %{
                 "mode" => "local",
                 "working_path" => repo_path
               })

      assert updated.working_path == repo_path
      assert updated.config["codex_app_server"]["mode"] == "local"
      assert updated.config["codex_app_server"]["working_path"] == repo_path
    end

    test "stores ssh launch config without storing secrets" do
      project = create_project()

      assert {:ok, updated} =
               CodexAppServers.configure(project, %{
                 "mode" => "ssh",
                 "ssh_target" => "devbox",
                 "remote_working_path" => "/srv/apps/demo"
               })

      config = updated.config["codex_app_server"]
      assert config["mode"] == "ssh"
      assert config["ssh_target"] == "devbox"
      assert config["remote_working_path"] == "/srv/apps/demo"
      refute Map.has_key?(config, "password")
      refute Map.has_key?(config, "private_key")
    end

    test "rejects ssh mode without target" do
      project = create_project()

      assert {:error, changeset} =
               CodexAppServers.configure(project, %{
                 "mode" => "ssh",
                 "remote_working_path" => "/srv/apps/demo"
               })

      assert %{config: [_]} = errors_on(changeset)
    end
  end

  describe "start/1" do
    test "rejects local launch when working path is missing" do
      project = create_project()

      assert {:ok, project} =
               CodexAppServers.configure(project, %{
                 "mode" => "local",
                 "working_path" => "/tmp/does-not-exist-#{System.unique_integer([:positive])}"
               })

      assert {:error, :working_path_not_available} = CodexAppServers.start(project.id)
    end

    test "starts and stops a local codex app-server process" do
      project = create_project()
      repo_path = make_git_dir()
      codex = make_fake_long_running_executable("codex")

      old_codex = Application.get_env(:samgita_provider, :codex_command)
      Application.put_env(:samgita_provider, :codex_command, codex)

      on_exit(fn ->
        Application.put_env(:samgita_provider, :codex_command, old_codex)
        CodexAppServers.stop(project.id)
      end)

      assert {:ok, project} =
               CodexAppServers.configure(project, %{
                 "mode" => "local",
                 "working_path" => repo_path
               })

      assert {:ok, status} = CodexAppServers.start(project.id)
      assert status.state == :running
      assert status.endpoint =~ "ws://127.0.0.1:"
      Process.sleep(50)

      assert {:ok, command} = CodexAppServers.connect_command(project.id)
      assert command == "codex --remote #{status.endpoint}"

      assert :ok = CodexAppServers.stop(project.id)
      assert %{state: :stopped} = CodexAppServers.status(project.id)
    end
  end

  defp create_project(attrs \\ %{}) do
    {:ok, project} = Projects.create_project(Map.merge(@valid_attrs, attrs))
    project
  end

  defp make_git_dir do
    dir = Path.join(System.tmp_dir!(), "samgita-codex-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, ".git"))
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp make_fake_long_running_executable(name) do
    dir = Path.join(System.tmp_dir!(), "samgita-bin-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, name)
    sh = System.find_executable("sh")

    File.write!(path, """
    #!#{sh}
    echo "$0 $@"
    trap 'exit 0' TERM INT
    while true; do sleep 1; done
    """)

    File.chmod!(path, 0o755)
    on_exit(fn -> File.rm_rf!(dir) end)
    path
  end
end
