defmodule Samgita.CodexAppServers do
  @moduledoc """
  Configures and manages Codex app-server processes launched by Samgita.
  """

  import Ecto.Changeset

  alias Samgita.CodexAppServers.Runtime
  alias Samgita.Domain.Project
  alias Samgita.Events
  alias Samgita.Projects

  @config_key "codex_app_server"
  @registry Samgita.CodexAppServers.Registry
  @supervisor Samgita.CodexAppServers.Supervisor

  @type status :: %{
          state: :running | :stopped,
          mode: String.t() | nil,
          endpoint: String.t() | nil,
          connect_command: String.t() | nil,
          logs: [String.t()]
        }

  @doc "Persist Codex app-server launch configuration for a project."
  @spec configure(Project.t(), map()) :: {:ok, Project.t()} | {:error, Ecto.Changeset.t()}
  def configure(%Project{} = project, attrs) when is_map(attrs) do
    with {:ok, launch_config} <- build_config(attrs) do
      project_attrs =
        %{
          config: Map.put(project.config || %{}, @config_key, launch_config)
        }
        |> maybe_put_working_path(launch_config)

      Projects.update_project(project, project_attrs)
    else
      {:error, message} -> {:error, config_changeset(project, message)}
    end
  end

  @doc "Start the configured Codex app-server for a project."
  @spec start(Ecto.UUID.t()) :: {:ok, status()} | {:error, term()}
  def start(project_id) do
    with {:ok, project} <- Projects.get_project(project_id),
         {:ok, launch_config} <- fetch_config(project),
         :ok <- validate_launch(project, launch_config),
         {:ok, pid} <- start_runtime(project, launch_config) do
      status = Runtime.status(pid)
      broadcast(project_id, status)
      {:ok, status}
    end
  end

  @doc "Stop the managed Codex app-server for a project."
  @spec stop(Ecto.UUID.t()) :: :ok
  def stop(project_id) do
    case Registry.lookup(@registry, project_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(@supervisor, pid)
        broadcast(project_id, status(project_id))
        :ok

      [] ->
        :ok
    end
  end

  @doc "Return runtime status if the server is running, otherwise persisted stopped status."
  @spec status(Ecto.UUID.t()) :: status()
  def status(project_id) do
    case Registry.lookup(@registry, project_id) do
      [{pid, _}] ->
        runtime_status(project_id, pid)

      [] ->
        stopped_status(project_mode(project_id))
    end
  end

  @doc "Return the Codex remote client command for a running app-server."
  @spec connect_command(Ecto.UUID.t()) :: {:ok, String.t()} | {:error, :not_running}
  def connect_command(project_id) do
    case status(project_id) do
      %{state: :running, connect_command: command} when is_binary(command) -> {:ok, command}
      _ -> {:error, :not_running}
    end
  end

  @doc false
  def config_key, do: @config_key

  defp build_config(attrs) do
    mode = attrs |> get_attr("mode") |> normalize_blank()

    case mode do
      "local" -> build_local_config(attrs)
      "ssh" -> build_ssh_config(attrs)
      _ -> {:error, "launch mode must be local or ssh"}
    end
  end

  defp build_local_config(attrs) do
    working_path = attrs |> get_attr("working_path") |> normalize_blank()

    if is_nil(working_path) do
      {:error, "working path can't be blank"}
    else
      {:ok, %{"mode" => "local", "working_path" => working_path}}
    end
  end

  defp build_ssh_config(attrs) do
    ssh_target = attrs |> get_attr("ssh_target") |> normalize_blank()
    remote_working_path = attrs |> get_attr("remote_working_path") |> normalize_blank()

    cond do
      is_nil(ssh_target) ->
        {:error, "ssh target can't be blank"}

      is_nil(remote_working_path) ->
        {:error, "remote working path can't be blank"}

      true ->
        {:ok,
         %{
           "mode" => "ssh",
           "ssh_target" => ssh_target,
           "remote_working_path" => remote_working_path
         }}
    end
  end

  defp get_attr(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, String.to_atom(key))
  end

  defp normalize_blank(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_blank(value), do: value

  defp maybe_put_working_path(attrs, %{"mode" => "local", "working_path" => path}) do
    Map.put(attrs, :working_path, path)
  end

  defp maybe_put_working_path(attrs, _config), do: attrs

  defp fetch_config(%Project{} = project) do
    case get_in(project.config || %{}, [@config_key]) do
      %{"mode" => mode} = config when mode in ["local", "ssh"] -> {:ok, config}
      _ -> {:ok, %{"mode" => "local", "working_path" => project.working_path}}
    end
  end

  defp validate_launch(project, %{"mode" => "local"} = config) do
    path = config["working_path"] || project.working_path

    cond do
      !is_binary(path) or String.trim(path) == "" ->
        {:error, :working_path_not_available}

      !File.dir?(path) ->
        {:error, :working_path_not_available}

      !File.dir?(Path.join(path, ".git")) ->
        {:error, :working_path_not_git_repo}

      true ->
        :ok
    end
  end

  defp validate_launch(_project, %{"mode" => "ssh"}), do: :ok

  defp start_runtime(project, launch_config) do
    case Registry.lookup(@registry, project.id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        DynamicSupervisor.start_child(
          @supervisor,
          {Runtime,
           project_id: project.id, project_name: project.name, launch_config: launch_config}
        )
    end
  end

  defp stopped_status(mode) do
    %{
      state: :stopped,
      mode: mode,
      endpoint: nil,
      connect_command: nil,
      logs: []
    }
  end

  defp runtime_status(project_id, pid) do
    if Process.alive?(pid) do
      Runtime.status(pid)
    else
      stopped_status(project_mode(project_id))
    end
  catch
    :exit, _ -> stopped_status(project_mode(project_id))
  end

  defp project_mode(project_id) do
    with {:ok, project} <- Projects.get_project(project_id),
         {:ok, config} <- fetch_config(project) do
      config["mode"]
    else
      _ -> nil
    end
  end

  defp broadcast(project_id, status) do
    Events.codex_app_server_changed(project_id, status)
  end

  defp config_changeset(project, message) do
    project
    |> Project.changeset(%{})
    |> add_error(:config, message)
  end
end
