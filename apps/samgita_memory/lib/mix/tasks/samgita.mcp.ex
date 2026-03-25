defmodule Mix.Tasks.Samgita.Mcp do
  @shortdoc "Starts the Samgita Memory MCP stdio server"

  @moduledoc """
  Starts the MCP (Model Context Protocol) stdio server for the Samgita Memory System.

  The server communicates via stdin/stdout using newline-delimited JSON-RPC 2.0.
  All logging is written to stderr.

  ## Usage

      mix samgita.mcp

  The server will block, reading JSON-RPC messages from stdin and writing
  responses to stdout until EOF is received.
  """

  use Mix.Task

  alias SamgitaMemory.MCP.Server

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    Server.run()
  end
end
