defmodule StandaloneCodex do
  @moduledoc "An independently started Codex client; no database or platform runtime."
  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.Stdio

  @doc "Initialize an explicitly selected executable and isolated local configuration directory."
  def start(binary, home, codex_home, workspace, capabilities \\ %{}) do
    case Session.start_link(
           transport:
             {Stdio,
              [
                executable: binary,
                args: [
                  "--config",
                  "approval_policy=\"never\"",
                  "--config",
                  "sandbox_mode=\"danger-full-access\"",
                  "app-server",
                  "--listen",
                  "stdio://"
                ],
                cwd: workspace,
                env: %{
                  "HOME" => home,
                  "CODEX_HOME" => codex_home,
                  "PATH" => Path.join(home, "bin") <> ":/usr/bin:/bin",
                  "RUST_LOG" => "off"
                }
              ]}
         ) do
      {:ok, pid} ->
        case initialize(pid, capabilities) do
          {:ok, _full_initialize_response} ->
            {:ok, pid}

          {:error, _failure} = result ->
            case close(pid) do
              :ok ->
                result

              {:error, cleanup_failure} ->
                {:error, {:initialization_cleanup_failed, result, cleanup_failure}}
            end
        end

      {:error, _failure} = result ->
        result
    end
  end

  @doc "Initialize a new connection explicitly, retaining the complete native response."
  def initialize(pid, capabilities \\ %{}) do
    Session.initialize(
      pid,
      %{"name" => "standalone_samgita_consumer", "version" => "0.1.0"},
      capabilities
    )
  end

  @doc "Keep the complete native result, including pagination and future extension fields."
  def list_threads(pid), do: Session.request(pid, "thread/list", %{"limit" => 10}, effect: :read)

  @doc "Send a native notification; local sent_unconfirmed is not a remote acknowledgement."
  def notify(pid, wire), do: Session.notify_native(pid, wire)

  @doc "Pull full ordered messages and exact interaction handles; no automatic approval."
  def events(pid), do: Session.drain(pid)

  @doc "Caller authorization must precede this explicit response to one current handle."
  def respond(pid, handle, result), do: Session.respond(pid, handle, result)

  def close(pid), do: Session.close(pid)
end
