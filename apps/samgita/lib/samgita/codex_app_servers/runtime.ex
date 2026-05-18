defmodule Samgita.CodexAppServers.Runtime do
  @moduledoc false

  use GenServer

  require Logger

  @registry Samgita.CodexAppServers.Registry
  @max_logs 80

  def start_link(opts) do
    project_id = Keyword.fetch!(opts, :project_id)
    GenServer.start_link(__MODULE__, opts, name: via(project_id))
  end

  def status(pid) when is_pid(pid), do: GenServer.call(pid, :status)

  @impl true
  def init(opts) do
    launch_config = Keyword.fetch!(opts, :launch_config)
    project_id = Keyword.fetch!(opts, :project_id)

    state = %{
      project_id: project_id,
      project_name: Keyword.get(opts, :project_name),
      launch_config: launch_config,
      mode: launch_config["mode"],
      endpoint: nil,
      connect_command: nil,
      port: nil,
      logs: []
    }

    {:ok, state, {:continue, :start_port}}
  end

  @impl true
  def handle_continue(:start_port, state) do
    case open_port(state.launch_config) do
      {:ok, port, endpoint} ->
        {:noreply,
         %{state | port: port, endpoint: endpoint, connect_command: connect_command(endpoint)}}

      {:error, reason} ->
        Logger.warning("Codex app-server failed to start: #{inspect(reason)}")
        {:stop, reason, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, public_status(state), state}
  end

  @impl true
  def handle_info({_port, {:data, data}}, state) do
    {:noreply, append_log(state, data)}
  end

  def handle_info({_port, {:exit_status, status}}, state) do
    {:stop, {:port_exit, status}, append_log(state, "codex app-server exited with #{status}")}
  end

  @impl true
  def terminate(_reason, %{port: port}) when not is_nil(port) do
    Port.close(port)
    :ok
  catch
    _, _ -> :ok
  end

  def terminate(_reason, _state), do: :ok

  defp open_port(%{"mode" => "local"} = config) do
    with {:ok, port_num} <- find_open_port(),
         {:ok, executable} <- codex_executable() do
      endpoint = "ws://127.0.0.1:#{port_num}"

      port =
        Port.open({:spawn_executable, executable}, [
          :binary,
          :exit_status,
          args: ["-C", config["working_path"], "app-server", "--listen", endpoint]
        ])

      {:ok, port, endpoint}
    end
  end

  defp open_port(%{"mode" => "ssh"} = config) do
    with {:ok, local_port} <- find_open_port(),
         {:ok, remote_port} <- find_open_port(),
         {:ok, executable} <- ssh_executable() do
      endpoint = "ws://127.0.0.1:#{local_port}"
      remote_endpoint = "ws://127.0.0.1:#{remote_port}"

      port =
        Port.open({:spawn_executable, executable}, [
          :binary,
          :exit_status,
          args: [
            "-L",
            "#{local_port}:127.0.0.1:#{remote_port}",
            config["ssh_target"],
            "codex",
            "-C",
            config["remote_working_path"],
            "app-server",
            "--listen",
            remote_endpoint
          ]
        ])

      {:ok, port, endpoint}
    end
  end

  defp public_status(state) do
    %{
      state: :running,
      mode: state.mode,
      endpoint: state.endpoint,
      connect_command: state.connect_command,
      logs: Enum.reverse(state.logs)
    }
  end

  defp connect_command(endpoint), do: "codex --remote #{endpoint}"

  defp append_log(state, data) do
    line =
      data
      |> to_string()
      |> String.trim()

    if line == "" do
      state
    else
      %{state | logs: [line | state.logs] |> Enum.take(@max_logs)}
    end
  end

  defp find_open_port do
    case :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}]) do
      {:ok, socket} ->
        {:ok, port} = :inet.port(socket)
        :gen_tcp.close(socket)
        {:ok, port}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp codex_executable do
    :samgita_provider
    |> Application.get_env(:codex_command, "codex")
    |> resolve_executable()
  end

  defp ssh_executable do
    :samgita_provider
    |> Application.get_env(:ssh_command, "ssh")
    |> resolve_executable()
  end

  defp resolve_executable(command) do
    cond do
      is_binary(command) and Path.type(command) == :absolute and File.exists?(command) ->
        {:ok, command}

      is_binary(command) ->
        case System.find_executable(command) do
          nil -> {:error, {:executable_not_found, command}}
          path -> {:ok, path}
        end

      true ->
        {:error, {:invalid_executable, command}}
    end
  end

  defp via(project_id), do: {:via, Registry, {@registry, project_id}}
end
