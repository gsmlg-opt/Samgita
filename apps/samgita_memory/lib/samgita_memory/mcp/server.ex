defmodule SamgitaMemory.MCP.Server do
  @moduledoc """
  MCP (Model Context Protocol) stdio server for the Samgita Memory System.

  Implements JSON-RPC 2.0 over stdin/stdout with newline-delimited messages.
  All logging goes to stderr to keep the stdio transport clean.
  """

  alias SamgitaMemory.MCP.Tools

  @protocol_version "2024-11-05"
  @server_name "samgita-memory"
  @server_version "0.1.0"

  @doc """
  Starts the MCP stdio server loop. Reads JSON-RPC messages from stdin
  and writes responses to stdout. Blocks until EOF on stdin.
  """
  def run do
    log("#{@server_name} MCP server starting (protocol #{@protocol_version})")
    loop()
  end

  @doc """
  Process a single JSON-RPC message string and return the response string
  (or nil for notifications). Useful for testing.
  """
  def handle_message(line) do
    case Jason.decode(line) do
      {:ok, request} ->
        handle_request(request)

      {:error, reason} ->
        error_response(nil, -32_700, "Parse error: #{inspect(reason)}")
    end
  end

  defp loop do
    case IO.read(:stdio, :line) do
      :eof ->
        log("EOF received, shutting down")
        :ok

      {:error, reason} ->
        log("Read error: #{inspect(reason)}")
        :ok

      line ->
        line = String.trim(line)

        if line != "" do
          case handle_message(line) do
            nil ->
              :ok

            response ->
              IO.write(:stdio, response <> "\n")
          end
        end

        loop()
    end
  end

  defp handle_request(%{"method" => "initialize", "id" => id}) do
    result = %{
      capabilities: %{tools: %{}},
      serverInfo: %{name: @server_name, version: @server_version},
      protocolVersion: @protocol_version
    }

    success_response(id, result)
  end

  defp handle_request(%{"method" => "notifications/initialized"}) do
    log("Client initialized")
    nil
  end

  defp handle_request(%{"method" => "tools/list", "id" => id}) do
    tools = Tools.definitions()
    success_response(id, %{tools: tools})
  end

  defp handle_request(%{"method" => "tools/call", "id" => id, "params" => params}) do
    tool_name = params["name"]
    arguments = params["arguments"] || %{}

    log("Calling tool: #{tool_name}")

    case Tools.execute(tool_name, arguments) do
      {:ok, data} ->
        content = [%{type: "text", text: Jason.encode!(data)}]
        success_response(id, %{content: content})

      {:error, reason} ->
        content = [%{type: "text", text: Jason.encode!(%{error: reason})}]
        success_response(id, %{content: content, isError: true})
    end
  end

  defp handle_request(%{"method" => "ping", "id" => id}) do
    success_response(id, %{})
  end

  defp handle_request(%{"method" => method, "id" => id}) do
    error_response(id, -32_601, "Method not found: #{method}")
  end

  defp handle_request(%{"method" => _method}) do
    # Notification without id - no response needed
    nil
  end

  defp handle_request(_) do
    error_response(nil, -32_600, "Invalid request")
  end

  defp success_response(id, result) do
    Jason.encode!(%{jsonrpc: "2.0", id: id, result: result})
  end

  defp error_response(id, code, message) do
    Jason.encode!(%{jsonrpc: "2.0", id: id, error: %{code: code, message: message}})
  end

  defp log(message) do
    IO.write(:stderr, "[#{@server_name}] #{message}\n")
  end
end
