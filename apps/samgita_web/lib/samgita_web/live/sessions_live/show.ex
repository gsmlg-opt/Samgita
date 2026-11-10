defmodule SamgitaWeb.SessionsLive.Show do
  @moduledoc """
  An interactive Codex session on one host: start a new session in a project
  folder or continue an existing one, send messages, watch Codex reply and work,
  answer its approval requests and stop a running turn.

  The conversation is the DuskMoon React chat (`dm_react_chat`): React owns the
  transcript and composer; this view pushes `chat:event` events (whole-message
  updates with per-message sequence numbers, or a snapshot) and answers the
  chat's `chat.send`, `chat.stop` and `chat.sync` requests.

  Codex owns the session. Samgita relays the operator's messages and decisions
  and renders the thread's live events; it stores no conversation and creates
  no Task or Attempt.
  """
  use SamgitaWeb, :live_view
  alias Samgita.{CodexHosts, Principal}
  alias SamgitaWeb.SessionsLive.Items

  @chat "session-chat"

  @impl true
  def mount(%{"host_id" => host_id} = params, _session, socket) do
    host = Enum.find(list_hosts(), &(&1["id"] == host_id))

    {:ok,
     assign(socket,
       page_title: "Session",
       host_id: host_id,
       host: host,
       thread_id: nil,
       subscribed: nil,
       title: nil,
       cwd: params["cwd"],
       items: [],
       running_turn: nil,
       requests: [],
       error: if(host, do: nil, else: "This Codex host does not exist."),
       # The chat's conversation is fixed for the life of its React root; a new
       # session keeps it when the URL changes to the created thread.
       conversation_id: params["thread_id"] || "new-" <> Ecto.UUID.generate(),
       chat: %{messages: [], sequences: %{}, runtime: nil}
     )}
  end

  @impl true
  def handle_params(%{"thread_id" => thread_id}, _uri, socket) do
    if socket.assigns.thread_id == thread_id do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(thread_id: thread_id, items: [])
       |> subscribe(thread_id)
       |> resume(thread_id)}
    end
  end

  def handle_params(_params, _uri, socket),
    do: {:noreply, assign(socket, title: socket.assigns.cwd && Path.basename(socket.assigns.cwd))}

  # The chat sends `{text}`; while Codex works, the message steers the running
  # turn. An error reply keeps the draft in the composer.
  @impl true
  def handle_event("chat.send", %{"text" => text}, socket) do
    with {:ok, socket} <- ensure_thread(socket),
         {:ok, turn_id} <-
           CodexHosts.send_message(
             Principal.operator(),
             socket.assigns.host_id,
             socket.assigns.thread_id,
             text,
             socket.assigns.running_turn
           ) do
      socket =
        socket
        |> assign(error: nil, running_turn: socket.assigns.running_turn || turn_id)
        |> publish()

      {:reply, %{status: "ok"}, socket}
    else
      {:error, error} -> {:reply, %{status: "error", message: message(error)}, socket}
    end
  end

  def handle_event("chat.stop", _params, %{assigns: %{running_turn: turn_id}} = socket)
      when is_binary(turn_id) do
    case CodexHosts.interrupt(
           Principal.operator(),
           socket.assigns.host_id,
           socket.assigns.thread_id,
           turn_id
         ) do
      :ok -> {:reply, %{status: "ok"}, socket}
      {:error, error} -> {:reply, %{status: "error", message: message(error)}, socket}
    end
  end

  def handle_event("chat.stop", _params, socket), do: {:reply, %{status: "ok"}, socket}

  # After a reconnect the chat asks for the authoritative transcript.
  def handle_event("chat.sync", _params, socket),
    do: {:reply, %{status: "ok"}, snapshot(socket)}

  def handle_event(event, _params, socket) when event in ["chat.retry", "chat.action"],
    do: {:reply, %{status: "error", message: "Not supported for Codex sessions."}, socket}

  def handle_event("decide", %{"key" => key, "decision" => decision}, socket) do
    case CodexHosts.respond_request(Principal.operator(), socket.assigns.host_id, key, decision) do
      :ok -> {:noreply, update(socket, :requests, &Enum.reject(&1, fn r -> r["key"] == key end))}
      {:error, error} -> {:noreply, assign(socket, error: message(error))}
    end
  end

  @impl true
  def handle_info({:codex_event, wire}, socket),
    do: {:noreply, socket |> Items.apply_event(wire) |> publish()}

  def handle_info({:codex_request, request}, socket),
    do:
      {:noreply,
       update(socket, :requests, fn requests ->
         Enum.reject(requests, &(&1["key"] == request["key"])) ++ [request]
       end)}

  def handle_info({:codex_request_closed, key}, socket),
    do: {:noreply, update(socket, :requests, &Enum.reject(&1, fn r -> r["key"] == key end))}

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:resume, {:ok, {{:ok, thread}, requests}}, socket) do
    {:noreply,
     socket
     |> assign(
       title: thread["title"],
       cwd: thread["cwd"],
       items: Items.from_turns(thread["turns"]),
       running_turn: Items.running_turn(thread["turns"]),
       requests: requests
     )
     |> snapshot()}
  end

  def handle_async(:resume, {:ok, {{:error, error}, _}}, socket),
    do: {:noreply, assign(socket, error: message(error))}

  def handle_async(:resume, {:exit, _}, socket),
    do: {:noreply, assign(socket, error: message(nil))}

  # Push what changed since the last push: each new or changed message as a
  # `chat.message` with its next sequence number. Messages are only appended or
  # updated in place; anything else (or only a runtime change) is a snapshot.
  defp publish(socket) do
    %{chat: chat} = socket.assigns
    messages = Items.messages(socket.assigns.items, socket.assigns.running_turn != nil)
    previous = Enum.map(chat.messages, & &1["id"])
    changed = Enum.reject(messages, &(&1 in chat.messages))

    cond do
      Enum.take(Enum.map(messages, & &1["id"]), length(previous)) != previous ->
        snapshot(socket)

      changed == [] and runtime(socket) == chat.runtime ->
        socket

      changed == [] ->
        snapshot(socket)

      true ->
        Enum.reduce(changed, socket, fn message, socket ->
          id = message["id"]
          sequence = Map.get(socket.assigns.chat.sequences, id, 0) + 1

          socket
          |> push_chat("chat.message", %{
            message_id: id,
            sequence: sequence,
            message: message
          })
          |> update(:chat, &put_in(&1, [:sequences, id], sequence))
        end)
        |> update(:chat, &%{&1 | messages: messages, runtime: runtime(socket)})
    end
  end

  defp snapshot(socket) do
    messages = Items.messages(socket.assigns.items, socket.assigns.running_turn != nil)
    sequences = Map.new(messages, &{&1["id"], 1})

    socket
    |> push_chat("chat.snapshot", %{messages: messages, sequences: sequences})
    |> assign(chat: %{messages: messages, sequences: sequences, runtime: runtime(socket)})
  end

  defp push_chat(socket, type, payload),
    do:
      push_event(
        socket,
        "chat:event",
        Map.merge(payload, %{
          id: @chat,
          conversation_id: socket.assigns.conversation_id,
          type: type,
          runtime: runtime(socket),
          admission: admission(socket)
        })
      )

  # Stop shows while a turn runs; messages may still be sent to steer it.
  defp runtime(socket), do: %{active: socket.assigns.running_turn != nil}

  defp admission(socket), do: %{canSubmit: socket.assigns.host != nil, allowWhileStreaming: true}

  defp resume(socket, thread_id) do
    host_id = socket.assigns.host_id

    start_async(socket, :resume, fn ->
      result = CodexHosts.resume_thread(Principal.operator(), host_id, thread_id)
      {:ok, requests} = CodexHosts.pending_requests(Principal.operator(), host_id, thread_id)
      {result, requests}
    end)
  end

  # A new session is created on the first message, in the chosen folder.
  defp ensure_thread(%{assigns: %{thread_id: id}} = socket) when is_binary(id), do: {:ok, socket}

  defp ensure_thread(socket) do
    case CodexHosts.start_thread(Principal.operator(), socket.assigns.host_id, socket.assigns.cwd) do
      {:ok, thread} ->
        socket =
          socket
          |> assign(thread_id: thread["id"], title: thread["title"] || socket.assigns.title)
          |> subscribe(thread["id"])
          |> push_patch(
            to: ~p"/sessions/#{socket.assigns.host_id}/#{thread["id"]}",
            replace: true
          )

        {:ok, socket}

      error ->
        error
    end
  end

  defp subscribe(socket, thread_id) do
    if connected?(socket) and socket.assigns.subscribed != thread_id do
      if socket.assigns.subscribed,
        do: Phoenix.PubSub.unsubscribe(Samgita.PubSub, topic(socket, socket.assigns.subscribed))

      Phoenix.PubSub.subscribe(Samgita.PubSub, topic(socket, thread_id))
      assign(socket, subscribed: thread_id)
    else
      socket
    end
  end

  defp topic(socket, thread_id),
    do: CodexHosts.Runtime.thread_topic(socket.assigns.host_id, thread_id)

  defp list_hosts do
    {:ok, hosts} = CodexHosts.list(Principal.operator())
    hosts
  end

  defp message(%Samgita.Error{code: :codex_unavailable}),
    do: "Codex is not connected. Start it on the Agent page and try again."

  defp message(%Samgita.Error{code: :invalid}), do: "Write a message first."
  defp message(%Samgita.Error{code: :codex_request_failed}), do: "Codex rejected the request."
  defp message(_), do: "Codex could not be reached."

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :chat_id, @chat)

    ~H"""
    <section class="flex flex-col gap-4" aria-labelledby="session-title">
      <header class="flex flex-wrap items-start justify-between gap-4">
        <div class="min-w-0">
          <h1 id="session-title" class="truncate text-2xl font-bold">
            {@title || (@cwd && Path.basename(@cwd)) || "Session"}
          </h1>
          <p class="truncate text-sm text-on-surface-variant">
            <span :if={@host}>{@host["agent_name"]}</span>
            <code :if={@cwd} class="ml-2">{@cwd}</code>
          </p>
        </div>
        <.dm_link navigate={~p"/projects"} class="font-semibold">Back to Projects</.dm_link>
      </header>

      <p :if={@error} id="session-error" role="alert" class="text-error">{@error}</p>

      <div
        :for={request <- @requests}
        id={"request-" <> request["key"]}
        class="rounded-xl border border-warning p-4"
      >
        <Items.request request={request} />
        <p :if={!Items.answerable?(request)} class="mt-2 text-sm text-on-surface-variant">
          Answer this request in a Codex app; Samgita cannot answer it yet.
        </p>
        <div :if={Items.answerable?(request)} class="mt-3 flex flex-wrap gap-2">
          <.dm_btn
            size="sm"
            variant="primary"
            phx-click="decide"
            phx-value-key={request["key"]}
            phx-value-decision="accept"
          >
            Approve
          </.dm_btn>
          <.dm_btn
            size="sm"
            phx-click="decide"
            phx-value-key={request["key"]}
            phx-value-decision="acceptForSession"
          >
            Approve for this session
          </.dm_btn>
          <.dm_btn
            size="sm"
            phx-click="decide"
            phx-value-key={request["key"]}
            phx-value-decision="decline"
          >
            Decline
          </.dm_btn>
        </div>
      </div>

      <.dm_react_chat
        id={@chat_id}
        hook="SessionChat"
        conversation_id={@conversation_id}
        label="Codex session"
        messages={[]}
        runtime={%{active: false}}
        admission={%{canSubmit: @host != nil, allowWhileStreaming: true}}
        class="block h-[calc(100dvh-14rem)] min-h-96 rounded-xl border border-outline-variant p-4"
      />
    </section>
    """
  end
end
