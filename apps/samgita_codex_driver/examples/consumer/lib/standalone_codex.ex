defmodule StandaloneCodex do
  @moduledoc "An independently started Codex client; no database or platform runtime."
  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.Stdio

  @doc "Initialize an explicitly selected executable and isolated local configuration directory."
  def start(binary, home, codex_home, workspace) do
    with {:ok, pid} <-
           Session.start_link(
             transport:
               {Stdio,
                [
                  executable: binary,
                  args: ["app-server", "--listen", "stdio://"],
                  cwd: workspace,
                  env: %{"HOME" => home, "CODEX_HOME" => codex_home, "RUST_LOG" => "off"}
                ]}
           ),
         {:ok, _full_initialize_response} <-
           Session.initialize(pid, %{
             "name" => "standalone_samgita_consumer",
             "version" => "0.1.0"
           }) do
      {:ok, pid}
    end
  end

  @doc "Keep the complete native result, including pagination and future extension fields."
  def list_threads(pid), do: Session.request(pid, "thread/list", %{"limit" => 10}, effect: :read)

  @doc "Pull full ordered messages and exact interaction handles; no automatic approval."
  def events(pid), do: Session.drain(pid)

  @doc "Caller authorization must precede this explicit response to one current handle."
  def respond(pid, handle, result), do: Session.respond(pid, handle, result)

  def close(pid), do: Session.close(pid)
end
