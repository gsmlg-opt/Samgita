defmodule Samgita.CodexHosts.Connection do
  @moduledoc """
  Owns one live Codex app-server Session for one configured host.

  Connects, initializes, records a new connection generation, and reconnects
  with bounded exponential backoff after any failure or disconnect. Status is
  evidence of reachability only. Closing this process closes only the client
  connection; it never stops the remote app-server or its threads.
  """
  use GenServer, restart: :permanent
  alias Samgita.CodexHosts
  alias Samgita.CodexHosts.Runtime
  alias SamgitaCodexDriver.Session
  alias Samgita.CodexHosts.Ssh
  alias SamgitaCodexDriver.Transport.{Command, UnixSocket, WebSocket}

  @min_backoff 1_000
  @max_backoff 60_000
  @drain_limit 1_000

  def start_link(host),
    do: GenServer.start_link(__MODULE__, host, name: Runtime.via(host.id, host.version))

  def child_spec(host),
    do: %{
      id: {__MODULE__, host.id},
      start: {__MODULE__, :start_link, [host]},
      restart: :permanent
    }

  def status(pid), do: GenServer.call(pid, :status)
  @doc "Ask for a fresh connection. Never waits, even while a connect is in progress."
  def reconnect(pid), do: GenServer.cast(pid, :reconnect)
  @doc "The initialized Session while connected, otherwise nil."
  def session(pid), do: GenServer.call(pid, :session)

  @doc "Approval requests from Codex still waiting for an answer, for one thread."
  def pending_requests(pid, thread_id), do: GenServer.call(pid, {:pending_requests, thread_id})

  @doc "Answer one pending Codex request (`{:ok, result}` or `{:error, error}`)."
  def respond(pid, key, result), do: GenServer.call(pid, {:respond, key, result})

  @impl true
  def init(host) do
    Process.flag(:trap_exit, true)

    state = %{
      host: host,
      session: nil,
      files: nil,
      generation: nil,
      backoff: backoff_config(:min),
      timer: nil,
      requests: %{},
      status: %{"state" => "connecting"}
    }

    {:ok, publish(state), {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state), do: {:noreply, connect(state)}

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state.status, state}

  def handle_call(:session, _from, state),
    do: {:reply, if(state.generation, do: state.session), state}

  def handle_call({:pending_requests, thread_id}, _from, state) do
    requests =
      for {key, %{thread_id: ^thread_id, wire: wire}} <- state.requests,
          do: %{"key" => key, "method" => wire["method"], "params" => wire["params"]}

    {:reply, requests, state}
  end

  def handle_call({:respond, key, result}, _from, state) do
    case {state.session, Map.pop(state.requests, key)} do
      {session, {%{handle: handle, thread_id: thread_id}, requests}} when is_pid(session) ->
        reply =
          case Session.respond(session, handle, result) do
            :ok ->
              Session.acknowledge_interaction_outcome(session, handle)
              :ok

            {:error, _} = error ->
              error
          end

        Runtime.broadcast_thread(state.host.id, thread_id, {:codex_request_closed, key})
        {:reply, reply, %{state | requests: requests}}

      _ ->
        {:reply, {:error, :not_pending}, state}
    end
  catch
    :exit, _ -> {:reply, {:error, :session_exited}, state}
  end

  @impl true
  def handle_cast(:reconnect, state) do
    state = state |> cancel_timer() |> close_session(:operator_reconnect)
    {:noreply, connect(%{state | backoff: backoff_config(:min)})}
  end

  @impl true
  def handle_info(:retry, state), do: {:noreply, connect(%{state | timer: nil})}

  def handle_info({:codex_driver, session, :events_available}, %{session: session} = state) do
    # Interactive sessions: route each thread's events to its viewers over
    # PubSub and keep server-request handles until the operator answers.
    # Task bridging (design §10/§11 later stages) will journal these events.
    {:noreply, drain(state)}
  end

  def handle_info({:codex_driver, session, {:gap, gap}}, %{session: session} = state),
    do: {:noreply, disconnected(state, reason(gap))}

  def handle_info({:EXIT, session, _reason}, %{session: session} = state),
    do: {:noreply, disconnected(%{state | session: nil}, :session_exited)}

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    close_session(state, :stopped)
    Runtime.broadcast(state.host.id, %{"state" => "stopped"})
    :ok
  end

  # Each step records what it acquired in the state, so a failure at any step
  # releases the session and private files acquired so far.
  defp connect(state) do
    host = state.host

    with {:ok, transport, files} <- transport(host),
         state = %{state | files: files},
         {:ok, state} <- step(state, ensure_daemon(host, files)),
         {:ok, state} <- step(state, start_session(transport), :session),
         {:ok, state} <- step(state, initialize(state.session), :init),
         {version, home} = state.init,
         state = Map.put(state, :server_version, version),
         identity = identity(state.session),
         {:ok, state} <-
           step(
             state,
             CodexHosts.record_connected(host.id, state.server_version, identity),
             :recorded
           ) do
      {version, recorded} = {state.server_version, state.recorded}
      state = Map.drop(state, [:server_version, :recorded, :init])

      %{
        state
        | generation: recorded.generation,
          backoff: backoff_config(:min),
          status: %{
            "state" => "connected",
            "generation" => recorded.generation,
            "server_version" => version,
            "home" => home,
            "connected_at" => DateTime.to_iso8601(recorded.last_connected_at)
          }
      }
      |> publish()
    else
      {:error, error} ->
        state |> close_session(:connect_failed) |> retry(code(error))

      {:error, error, state} ->
        state
        |> Map.drop([:server_version, :recorded, :init])
        |> close_session(:connect_failed)
        |> retry(code(error))
    end
  end

  defp step(state, :ok), do: {:ok, state}
  defp step(state, {:error, error}), do: {:error, error, state}
  defp step(state, {:ok, value}, key), do: {:ok, Map.put(state, key, value)}
  defp step(state, {:error, error}, _key), do: {:error, error, state}

  defp disconnected(state, reason) do
    if state.generation,
      do: CodexHosts.record_disconnected(state.host.id, state.generation, reason)

    state |> close_session(reason) |> retry(reason)
  end

  defp retry(state, error) do
    delay = jitter(state.backoff)
    timer = Process.send_after(self(), :retry, delay)
    retry_at = DateTime.add(DateTime.utc_now(), delay, :millisecond)

    %{
      state
      | timer: timer,
        generation: nil,
        backoff: min(state.backoff * 2, backoff_config(:max)),
        status: %{
          "state" => "backoff",
          "error" => to_string(error),
          "retry_at" => DateTime.to_iso8601(retry_at)
        }
    }
    |> publish()
  end

  # Approvals wait for a person in the browser, so allow up to 30 minutes.
  defp start_session(transport),
    do:
      Session.start_link(
        owner: self(),
        schema_mode: :compatible,
        transport: transport,
        interaction_timeout_ms: 1_800_000
      )

  defp transport(%{transport: "ssh"} = host) do
    case Ssh.prepare(host) do
      {:ok, prepared} -> {:ok, {Command, prepared.transport}, prepared}
      {:error, _} = error -> error
    end
  end

  # The local Codex daemon (the one the Codex app uses) listens on a control
  # socket under the Codex home. Samgita connects only; it never starts it.
  defp transport(%{transport: "local"}) do
    path = local_socket()

    # The daemon publishes the socket as a symlink to its runtime directory.
    case File.stat(path) do
      {:ok, %{type: :other}} -> {:ok, {UnixSocket, [socket_path: path]}, nil}
      _ -> {:error, :codex_daemon_not_running}
    end
  end

  defp transport(host) do
    case transport_opts(host) do
      {:ok, opts} -> {:ok, {WebSocket, opts}, nil}
      {:error, _} = error -> error
    end
  end

  defp ensure_daemon(%{transport: "ssh", ensure_daemon: true} = host, prepared),
    do: Ssh.ensure_daemon(host, prepared)

  defp ensure_daemon(_host, _files), do: :ok

  defp initialize(session) do
    info = %{"name" => "samgita", "version" => app_version()}

    # Codex projects (`project/*`) are part of the experimental API.
    case Session.initialize(session, info, %{"experimentalApi" => true}) do
      # The user's home on the Codex machine (parent of the reported Codex
      # home, `~/.codex` by default) is the starting folder for choosing projects.
      {:ok, wire} -> {:ok, {server_version(wire), home(wire)}}
      {:error, _} = error -> error
    end
  catch
    :exit, _ -> {:error, :session_exited}
  end

  @doc """
  Connect once, read the Codex identity and close. Used before adding a host to
  detect a machine that is already configured. Never starts a connection process.
  """
  def identify(host) do
    with {:ok, transport, files} <- transport(host) do
      try do
        with {:ok, session} <- start_session(transport) do
          try do
            with {:ok, _version} <- initialize(session), do: {:ok, identity(session)}
          after
            Session.close(session)
          end
        end
      after
        Ssh.cleanup(files)
      end
    end
  catch
    :exit, _ -> {:error, :unreachable}
  end

  # One machine (one Codex home) has one installation ID. Failure is tolerated:
  # older or restricted servers simply report no identity.
  defp identity(session) do
    case Session.request(session, "remoteControl/status/read", nil, timeout_ms: 5_000) do
      {:ok, %{"result" => %{"installationId" => id} = result}} when is_binary(id) ->
        %{installation_id: id, machine_name: result["serverName"]}

      _ ->
        %{installation_id: nil, machine_name: nil}
    end
  catch
    :exit, _ -> %{installation_id: nil, machine_name: nil}
  end

  defp home(%{"result" => %{"codexHome" => codex_home}}) when is_binary(codex_home),
    do: Path.dirname(codex_home)

  defp home(_), do: nil

  @doc false
  def server_version(%{"result" => %{"userAgent" => agent}}) when is_binary(agent) do
    case Regex.run(~r/\A[^\/\s]+\/([0-9A-Za-z][0-9A-Za-z.+-]{0,63})/, agent) do
      [_, version] -> version
      _ -> nil
    end
  end

  def server_version(_), do: nil

  @doc false
  def local_socket do
    configured = Keyword.get(Application.get_env(:samgita, :codex_hosts, []), :local_socket)
    home = System.get_env("CODEX_HOME") || Path.join(System.user_home!(), ".codex")
    configured || Path.join([home, "app-server-control", "app-server-control.sock"])
  end

  defp transport_opts(%{transport: "websocket"} = host) do
    with {:ok, token} <- token(host.token_ref),
         {:ok, address} <- address(host.connect_address) do
      opts =
        [url: host.url, allow_insecure: host.allow_insecure == true]
        |> put_present(:token, token)
        |> put_present(:connect_address, address)

      {:ok, opts}
    end
  end

  defp transport_opts(_host), do: {:error, :unsupported_transport}

  defp token(nil), do: {:ok, nil}

  defp token(reference) do
    case Application.get_env(:samgita, :codex_host_secrets, %{}) do
      %{^reference => value} when is_binary(value) and byte_size(value) in 1..8192 ->
        if String.contains?(value, ["\r", "\n"]),
          do: {:error, :credential_unavailable},
          else: {:ok, value}

      _ ->
        {:error, :credential_unavailable}
    end
  end

  defp address(nil), do: {:ok, nil}

  defp address(value) do
    case :inet.parse_strict_address(String.to_charlist(value)) do
      {:ok, address} -> {:ok, address}
      _ -> {:error, :invalid_transport_options}
    end
  end

  defp put_present(opts, _key, nil), do: opts
  defp put_present(opts, key, value), do: Keyword.put(opts, key, value)

  defp drain(state) do
    case Session.drain(state.session, @drain_limit) do
      {:ok, [_ | _] = events} -> events |> Enum.reduce(state, &route/2) |> drain()
      _ -> state
    end
  catch
    :exit, _ -> state
  end

  defp route(%{kind: :notification, wire: wire}, state) do
    case thread_id(wire["params"]) do
      nil ->
        state

      id ->
        tap(state, fn _ -> Runtime.broadcast_thread(state.host.id, id, {:codex_event, wire}) end)
    end
  end

  defp route(%{kind: :server_request, wire: wire, handle: handle}, state) do
    key = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    thread_id = thread_id(wire["params"])

    if thread_id,
      do:
        Runtime.broadcast_thread(
          state.host.id,
          thread_id,
          {:codex_request,
           %{"key" => key, "method" => wire["method"], "params" => wire["params"]}}
        )

    %{
      state
      | requests:
          Map.put(state.requests, key, %{handle: handle, wire: wire, thread_id: thread_id})
    }
  end

  defp route(%{kind: :interaction_expired, handle: handle}, state) do
    {expired, requests} = Enum.split_with(state.requests, fn {_, r} -> r.handle == handle end)

    for {key, %{thread_id: id}} <- expired,
        id != nil,
        do: Runtime.broadcast_thread(state.host.id, id, {:codex_request_closed, key})

    %{state | requests: Map.new(requests)}
  end

  defp route(_event, state), do: state

  defp thread_id(%{"threadId" => id}) when is_binary(id), do: id
  defp thread_id(%{"thread" => %{"id" => id}}) when is_binary(id), do: id
  defp thread_id(%{"conversationId" => id}) when is_binary(id), do: id
  defp thread_id(_), do: nil

  defp close_session(%{session: nil} = state, _reason), do: release_files(state)

  defp close_session(%{session: session} = state, _reason) do
    try do
      Session.close(session)
    catch
      :exit, _ -> :ok
    end

    # A closed session can no longer answer its pending requests.
    release_files(%{state | session: nil, requests: %{}})
  end

  # Private SSH files live exactly as long as one session attempt.
  defp release_files(%{files: nil} = state), do: state

  defp release_files(%{files: files} = state) do
    Ssh.cleanup(files)
    %{state | files: nil}
  end

  defp cancel_timer(%{timer: nil} = state), do: state

  defp cancel_timer(%{timer: timer} = state) do
    Process.cancel_timer(timer)
    %{state | timer: nil}
  end

  defp publish(state) do
    Runtime.broadcast(state.host.id, state.status)
    state
  end

  # Only fixed atoms leave this process: no upstream message, URL or token.
  defp code(%{code: code}) when is_atom(code), do: code
  defp code(code) when is_atom(code), do: code
  defp code(_), do: :connect_failed

  defp reason(%{reason: reason}) when is_atom(reason), do: reason
  defp reason(_), do: :disconnected

  defp jitter(delay), do: delay + :rand.uniform(max(div(delay, 5), 1)) - 1

  defp backoff_config(bound) do
    config = Application.get_env(:samgita, :codex_hosts, [])

    case bound do
      :min -> Keyword.get(config, :min_backoff_ms, @min_backoff)
      :max -> Keyword.get(config, :max_backoff_ms, @max_backoff)
    end
  end

  defp app_version, do: to_string(Application.spec(:samgita, :vsn) || "0.0.0")
end
