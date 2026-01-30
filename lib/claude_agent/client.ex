defmodule ClaudeAgent.Client do
  @moduledoc """
  Claude API client using http_fetch.

  Provides access to Claude's Messages API with support for:
  - Tool use (file operations, bash, etc.)
  - Streaming responses
  - Multi-turn conversations
  - Agent coordination for RARV cycle
  """

  require Logger

  @api_base_url "https://api.anthropic.com/v1"
  @default_model "claude-sonnet-4-5-20250929"
  @anthropic_version "2023-06-01"

  @type message :: %{
          role: String.t(),
          content: String.t() | list(map())
        }

  @type tool :: %{
          name: String.t(),
          description: String.t(),
          input_schema: map()
        }

  @type options :: [
          model: String.t(),
          max_tokens: integer(),
          temperature: float(),
          system: String.t(),
          tools: list(tool()),
          stream: boolean()
        ]

  @doc """
  Send a message to Claude and get a response.

  ## Options

  - `:model` - Model to use (default: claude-sonnet-4-5-20250929)
  - `:max_tokens` - Maximum tokens in response (default: 4096)
  - `:temperature` - Sampling temperature (default: 1.0)
  - `:system` - System prompt
  - `:tools` - List of available tools
  - `:stream` - Enable streaming (default: false)

  ## Examples

      iex> ClaudeAgent.Client.message([
      ...>   %{role: "user", content: "Hello!"}
      ...> ])
      {:ok, %{content: [%{"type" => "text", "text" => "Hello! How can I help?"}]}}

      iex> ClaudeAgent.Client.message(
      ...>   [%{role: "user", content: "Read file.txt"}],
      ...>   tools: ClaudeAgent.Tools.all()
      ...> )
      {:ok, %{content: [%{"type" => "tool_use", ...}]}}
  """
  @spec message(list(message()), options()) :: {:ok, map()} | {:error, term()}
  def message(messages, opts \\ []) do
    api_key = get_api_key()

    body =
      %{
        model: opts[:model] || @default_model,
        max_tokens: opts[:max_tokens] || 4096,
        messages: messages
      }
      |> maybe_add(:temperature, opts[:temperature])
      |> maybe_add(:system, opts[:system])
      |> maybe_add(:tools, opts[:tools])
      |> maybe_add(:stream, opts[:stream])

    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", @anthropic_version},
      {"content-type", "application/json"}
    ]

    promise = HTTP.fetch("#{@api_base_url}/messages",
      method: :post,
      headers: headers,
      body: Jason.encode!(body)
    )

    case HTTP.Promise.await(promise) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %{status: status, body: response_body}} ->
        Logger.error("Claude API error: #{status} - #{response_body}")
        {:error, {:api_error, status, response_body}}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Send a message with streaming enabled.

  Returns a stream of Server-Sent Events (SSE) that can be processed
  with Stream functions.

  ## Examples

      iex> ClaudeAgent.Client.stream([
      ...>   %{role: "user", content: "Write a story"}
      ...> ])
      ...> |> Stream.each(&IO.inspect/1)
      ...> |> Stream.run()
  """
  @spec stream(list(message()), options()) :: Enumerable.t()
  def stream(messages, opts \\ []) do
    api_key = get_api_key()

    body =
      %{
        model: opts[:model] || @default_model,
        max_tokens: opts[:max_tokens] || 4096,
        messages: messages,
        stream: true
      }
      |> maybe_add(:temperature, opts[:temperature])
      |> maybe_add(:system, opts[:system])
      |> maybe_add(:tools, opts[:tools])

    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", @anthropic_version},
      {"content-type", "application/json"}
    ]

    # TODO: Implement streaming with http_fetch
    # For now, return a stream that makes a single request
    Stream.resource(
      fn ->
        promise = HTTP.fetch("#{@api_base_url}/messages",
          method: :post,
          headers: headers,
          body: Jason.encode!(body)
        )

        case HTTP.Promise.await(promise) do
          {:ok, %{status: 200, body: response_body}} ->
            {:ok, Jason.decode!(response_body)}

          {:error, reason} ->
            {:error, reason}
        end
      end,
      fn
        {:ok, response} -> {[response], :done}
        {:error, _} = error -> {[error], :done}
        :done -> {:halt, :done}
      end,
      fn _ -> :ok end
    )
  end

  @doc """
  Execute a tool use request from Claude.

  Takes a tool_use block from Claude's response and executes the
  corresponding tool, returning the result.

  ## Examples

      iex> tool_use = %{
      ...>   "type" => "tool_use",
      ...>   "id" => "toolu_123",
      ...>   "name" => "read_file",
      ...>   "input" => %{"path" => "/tmp/file.txt"}
      ...> }
      iex> ClaudeAgent.Client.execute_tool(tool_use)
      {:ok, %{tool_use_id: "toolu_123", content: "file contents"}}
  """
  @spec execute_tool(map()) :: {:ok, map()} | {:error, term()}
  def execute_tool(%{"type" => "tool_use", "id" => id, "name" => name, "input" => input}) do
    case ClaudeAgent.Tools.execute(name, input) do
      {:ok, result} ->
        {:ok, %{
          type: "tool_result",
          tool_use_id: id,
          content: result
        }}

      {:error, reason} ->
        {:ok, %{
          type: "tool_result",
          tool_use_id: id,
          content: "Error: #{inspect(reason)}",
          is_error: true
        }}
    end
  end

  # Private helpers

  defp get_api_key do
    System.get_env("ANTHROPIC_API_KEY") ||
      Application.get_env(:samgita, :anthropic_api_key) ||
      raise "ANTHROPIC_API_KEY not configured"
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
end
