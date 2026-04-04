defmodule SamgitaProvider.Synapsis do
  @moduledoc """
  Provider that connects to a Synapsis instance via HTTP API.
  Synapsis provides persistent sessions, tool execution, and workspace management.
  """

  @behaviour SamgitaProvider.Provider

  require Logger

  alias SamgitaProvider.Session

  @default_timeout 300_000

  @impl true
  def query(prompt, opts \\ []) do
    case start_session(Keyword.get(opts, :system_prompt, ""), opts) do
      {:ok, session} ->
        case send_message(session, prompt) do
          {:ok, response, session} ->
            close_session(session)
            {:ok, response}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def start_session(system_prompt, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint) || default_endpoint()
    api_key = Keyword.get(opts, :api_key) || default_api_key()
    model = Keyword.get(opts, :model, "sonnet")

    body = %{
      "system_prompt" => system_prompt,
      "model" => model,
      "mode" => "build",
      "working_directory" => Keyword.get(opts, :working_directory)
    }

    case post(endpoint, "/api/sessions", body, api_key) do
      {:ok, %{"id" => remote_id}} ->
        session = Session.new(__MODULE__, system_prompt, opts)

        session = %{
          session
          | state: %{
              endpoint: endpoint,
              remote_session_id: remote_id,
              api_key: api_key
            }
        }

        {:ok, session}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def send_message(%Session{} = session, message) do
    %{endpoint: endpoint, remote_session_id: remote_id, api_key: api_key} = session.state

    body = %{"content" => message}

    case post(endpoint, "/api/sessions/#{remote_id}/messages", body, api_key) do
      {:ok, %{"content" => response_text} = resp} ->
        usage = Map.get(resp, "usage", %{})
        tokens = Map.get(usage, "input_tokens", 0) + Map.get(usage, "output_tokens", 0)

        updated =
          session
          |> Session.increment_message_count()
          |> Session.add_tokens(tokens)

        {:ok, response_text, updated}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def stream_message(%Session{} = session, message, subscriber) do
    %{endpoint: endpoint, remote_session_id: remote_id, api_key: api_key} = session.state

    ref = make_ref()
    body = %{"content" => message, "stream" => true}

    Task.start(fn ->
      case post_stream(
             endpoint,
             "/api/sessions/#{remote_id}/messages",
             body,
             api_key,
             subscriber,
             ref
           ) do
        {:ok, _} -> send(subscriber, {:stream_done, ref})
        {:error, reason} -> send(subscriber, {:stream_error, ref, reason})
      end
    end)

    {:ok, ref, Session.increment_message_count(session)}
  end

  @impl true
  def close_session(%Session{} = session) do
    %{endpoint: endpoint, remote_session_id: remote_id, api_key: api_key} = session.state
    delete(endpoint, "/api/sessions/#{remote_id}", api_key)
    :ok
  rescue
    _ -> :ok
  end

  @impl true
  def capabilities do
    %{
      supports_streaming: true,
      supports_tools: true,
      supports_multi_turn: true,
      max_context_tokens: 200_000,
      available_models: ["opus", "sonnet", "haiku"]
    }
  end

  @impl true
  def health_check do
    endpoint = default_endpoint()
    api_key = default_api_key()

    case get(endpoint, "/health", api_key) do
      {:ok, %{"status" => "ok"}} -> :ok
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # HTTP helpers using Finch

  defp post(endpoint, path, body, api_key) do
    url = endpoint <> path
    json_body = Jason.encode!(body)

    request = Finch.build(:post, url, headers(api_key), json_body)

    case Finch.request(request, finch_name(), receive_timeout: @default_timeout) do
      {:ok, %Finch.Response{status: status, body: resp_body}} when status in 200..299 ->
        Jason.decode(resp_body)

      {:ok, %Finch.Response{status: 429}} ->
        {:error, :rate_limit}

      {:ok, %Finch.Response{status: 503}} ->
        {:error, :unavailable}

      {:ok, %Finch.Response{status: status, body: resp_body}} ->
        {:error, "HTTP #{status}: #{String.slice(resp_body, 0, 200)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp post_stream(endpoint, path, body, api_key, subscriber, ref) do
    url = endpoint <> path
    json_body = Jason.encode!(body)
    request = Finch.build(:post, url, headers(api_key), json_body)

    Finch.stream(request, finch_name(), nil, fn
      {:status, _status}, acc ->
        acc

      {:headers, _headers}, acc ->
        acc

      {:data, data}, acc ->
        send(subscriber, {:stream_chunk, ref, data})
        acc
    end)
  end

  defp get(endpoint, path, api_key) do
    url = endpoint <> path
    request = Finch.build(:get, url, headers(api_key))

    case Finch.request(request, finch_name(), receive_timeout: 10_000) do
      {:ok, %Finch.Response{status: status, body: body}} when status in 200..299 ->
        Jason.decode(body)

      {:ok, %Finch.Response{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp delete(endpoint, path, api_key) do
    url = endpoint <> path
    request = Finch.build(:delete, url, headers(api_key))
    Finch.request(request, finch_name(), receive_timeout: 10_000)
  end

  defp headers(api_key) do
    [{"content-type", "application/json"}, {"authorization", "Bearer #{api_key}"}]
  end

  defp default_endpoint do
    Application.get_env(:samgita_provider, :synapsis_endpoint, "http://localhost:4000")
  end

  defp default_api_key do
    Application.get_env(:samgita_provider, :synapsis_api_key, "")
  end

  defp finch_name do
    Application.get_env(:samgita_provider, :finch_name, Samgita.Finch)
  end
end
