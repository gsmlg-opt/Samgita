defmodule SamgitaProvider.ClaudeAPI do
  @moduledoc """
  Provider that calls the Anthropic Messages API directly via HTTP.
  Session state is the accumulated messages list.
  """

  @behaviour SamgitaProvider.Provider

  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @api_version "2023-06-01"
  @default_max_tokens 4096

  alias SamgitaProvider.Session

  # Required callback
  @impl true
  def query(prompt, opts \\ []) do
    {:ok, session} = start_session(Keyword.get(opts, :system_prompt, ""), opts)

    case send_message(session, prompt) do
      {:ok, response, _session} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def start_session(system_prompt, opts \\ []) do
    session = Session.new(__MODULE__, system_prompt, opts)
    # State stores accumulated messages and system prompt
    session = %{session | state: %{messages: [], system_prompt: system_prompt}}
    {:ok, session}
  end

  @impl true
  def send_message(%Session{} = session, message) do
    messages = session.state.messages ++ [%{"role" => "user", "content" => message}]

    body = build_request_body(session, messages)

    case do_request(body) do
      {:ok, response_text, usage} ->
        updated_messages = messages ++ [%{"role" => "assistant", "content" => response_text}]

        updated_session = %{
          session
          | state: %{session.state | messages: updated_messages},
            message_count: session.message_count + 1,
            total_tokens:
              session.total_tokens + (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0)
        }

        {:ok, response_text, updated_session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def stream_message(%Session{} = session, message, subscriber) do
    messages = session.state.messages ++ [%{"role" => "user", "content" => message}]
    body = build_request_body(session, messages) |> Map.put("stream", true)

    ref = make_ref()

    # Start async streaming
    Task.start(fn ->
      case do_stream_request(body, subscriber, ref) do
        {:ok, _full_response, _usage} ->
          send(subscriber, {:stream_done, ref})

        {:error, reason} ->
          send(subscriber, {:stream_error, ref, reason})
      end
    end)

    updated_session = Session.increment_message_count(session)
    {:ok, ref, updated_session}
  end

  @impl true
  def close_session(%Session{} = _session) do
    # No remote state to clean up — messages are in-process
    :ok
  end

  @impl true
  def capabilities do
    %{
      supports_streaming: true,
      supports_tools: true,
      supports_multi_turn: true,
      max_context_tokens: 200_000,
      available_models: [
        "claude-sonnet-4-20250514",
        "claude-opus-4-20250514",
        "claude-haiku-4-5-20251001"
      ]
    }
  end

  @impl true
  def health_check do
    # Simple check — try to reach the API
    case do_request(%{
           "model" => "claude-haiku-4-5-20251001",
           "max_tokens" => 1,
           "messages" => [%{"role" => "user", "content" => "hi"}]
         }) do
      {:ok, _, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helpers

  defp build_request_body(session, messages) do
    model = map_model(session.model)
    max_tokens = Keyword.get(session.opts || [], :max_tokens, @default_max_tokens)

    body = %{
      "model" => model,
      "max_tokens" => max_tokens,
      "messages" => messages
    }

    system_prompt = session.state.system_prompt

    if system_prompt && system_prompt != "" do
      Map.put(body, "system", system_prompt)
    else
      body
    end
  end

  defp map_model("opus"), do: "claude-opus-4-20250514"
  defp map_model("sonnet"), do: "claude-sonnet-4-20250514"
  defp map_model("haiku"), do: "claude-haiku-4-5-20251001"
  # pass through full model IDs
  defp map_model(model), do: model

  defp do_request(body) do
    json_body = Jason.encode!(body)

    request = Finch.build(:post, @api_url, headers(), json_body)

    case Finch.request(request, finch_name()) do
      {:ok, %Finch.Response{status: 200, body: resp_body}} ->
        parse_response_body(resp_body)

      {:ok, %Finch.Response{status: 429}} ->
        {:error, :rate_limit}

      {:ok, %Finch.Response{status: 529}} ->
        {:error, :overloaded}

      {:ok, %Finch.Response{status: status, body: resp_body}} ->
        {:error, "HTTP #{status}: #{String.slice(resp_body, 0, 200)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_response_body(resp_body) do
    case Jason.decode(resp_body) do
      {:ok, %{"content" => [%{"text" => text} | _], "usage" => usage}} ->
        {:ok, text, usage}

      {:ok, %{"content" => []}} ->
        {:error, :empty_response}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, _} ->
        {:error, :json_parse_error}
    end
  end

  defp do_stream_request(body, subscriber, ref) do
    json_body = Jason.encode!(body)

    request =
      Finch.build(
        :post,
        @api_url,
        headers(),
        json_body
      )

    acc = %{text: "", usage: %{}}

    case Finch.stream(
           request,
           finch_name(),
           acc,
           fn
             {:status, _status}, acc ->
               acc

             {:headers, _headers}, acc ->
               acc

             {:data, data}, acc ->
               handle_stream_data(data, acc, subscriber, ref)
           end
         ) do
      {:ok, %{text: text, usage: usage}} ->
        {:ok, text, usage}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_stream_data(data, acc, subscriber, ref) do
    {new_text, new_usage} = parse_sse_chunk(data)
    if new_text != "", do: send(subscriber, {:stream_chunk, ref, new_text})
    %{acc | text: acc.text <> new_text, usage: Map.merge(acc.usage, new_usage)}
  end

  defp parse_sse_chunk(data) do
    data
    |> String.split("\n")
    |> Enum.reduce({"", %{}}, fn line, acc -> parse_sse_line(line, acc) end)
  end

  defp parse_sse_line("data: " <> json_str, {text, usage}) do
    parse_sse_event(Jason.decode(json_str), text, usage)
  end

  defp parse_sse_line(_line, acc), do: acc

  defp parse_sse_event(
         {:ok, %{"type" => "content_block_delta", "delta" => %{"text" => chunk}}},
         text,
         usage
       ) do
    {text <> chunk, usage}
  end

  defp parse_sse_event({:ok, %{"type" => "message_delta", "usage" => u}}, text, usage) do
    {text, Map.merge(usage, u)}
  end

  defp parse_sse_event(_other, text, usage), do: {text, usage}

  defp headers do
    api_key = Application.get_env(:samgita_provider, :anthropic_api_key, "")

    [
      {"content-type", "application/json"},
      {"x-api-key", api_key},
      {"anthropic-version", @api_version}
    ]
  end

  defp finch_name do
    Application.get_env(:samgita_provider, :finch_name, Samgita.Finch)
  end
end
