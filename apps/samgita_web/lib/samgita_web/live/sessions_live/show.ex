defmodule SamgitaWeb.SessionsLive.Show do
  @moduledoc """
  An interactive Codex session on one host: start a new session in a project
  folder or continue an existing one, send messages, watch Codex reply and work,
  answer its approval requests and stop a running turn.

  Codex owns the session. Samgita relays the operator's messages and decisions
  and renders the thread's live events; it stores no conversation and creates
  no Task or Attempt.
  """
  use SamgitaWeb, :live_view
  alias Samgita.{CodexHosts, Principal}
  alias SamgitaWeb.SessionsLive.Items

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
       loading: false,
       message: ""
     )}
  end

  @impl true
  def handle_params(%{"thread_id" => thread_id}, _uri, socket) do
    if socket.assigns.thread_id == thread_id do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(thread_id: thread_id, loading: true, items: [])
       |> subscribe(thread_id)
       |> resume(thread_id)}
    end
  end

  def handle_params(_params, _uri, socket),
    do: {:noreply, assign(socket, title: socket.assigns.cwd && Path.basename(socket.assigns.cwd))}

  @impl true
  def handle_event("change", %{"message" => text}, socket),
    do: {:noreply, assign(socket, message: text)}

  def handle_event("send", %{"message" => text}, socket) do
    with {:ok, socket} <- ensure_thread(socket),
         {:ok, turn_id} <-
           CodexHosts.send_message(
             Principal.operator(),
             socket.assigns.host_id,
             socket.assigns.thread_id,
             text
           ) do
      {:noreply,
       assign(socket,
         message: "",
         error: nil,
         running_turn: socket.assigns.running_turn || turn_id
       )}
    else
      {:error, error} -> {:noreply, assign(socket, message: text, error: message(error))}
    end
  end

  def handle_event("stop", _params, %{assigns: %{running_turn: turn_id}} = socket)
      when is_binary(turn_id) do
    case CodexHosts.interrupt(
           Principal.operator(),
           socket.assigns.host_id,
           socket.assigns.thread_id,
           turn_id
         ) do
      :ok -> {:noreply, socket}
      {:error, error} -> {:noreply, assign(socket, error: message(error))}
    end
  end

  def handle_event("decide", %{"key" => key, "decision" => decision}, socket) do
    case CodexHosts.respond_request(Principal.operator(), socket.assigns.host_id, key, decision) do
      :ok -> {:noreply, update(socket, :requests, &Enum.reject(&1, fn r -> r["key"] == key end))}
      {:error, error} -> {:noreply, assign(socket, error: message(error))}
    end
  end

  @impl true
  def handle_info({:codex_event, wire}, socket), do: {:noreply, Items.apply_event(socket, wire)}

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
     assign(socket,
       loading: false,
       title: thread["title"],
       cwd: thread["cwd"],
       items: Items.from_turns(thread["turns"]),
       running_turn: Items.running_turn(thread["turns"]),
       requests: requests
     )}
  end

  def handle_async(:resume, {:ok, {{:error, error}, _}}, socket),
    do: {:noreply, assign(socket, loading: false, error: message(error))}

  def handle_async(:resume, {:exit, _}, socket),
    do: {:noreply, assign(socket, loading: false, error: message(nil))}

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
    ~H"""
    <section class="flex min-h-[calc(100vh-10rem)] flex-col gap-4" aria-labelledby="session-title">
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
        id="session-items"
        class="flex-1 space-y-4 rounded-xl border border-outline-variant p-4"
        phx-hook={nil}
      >
        <p :if={@loading} class="text-on-surface-variant">Loading session…</p>
        <p :if={!@loading and @items == []} class="text-on-surface-variant">
          {if @thread_id,
            do: "No messages yet.",
            else: "Describe what Codex should do in this project."}
        </p>
        <div :for={item <- @items} id={"item-" <> item["id"]}>
          <Items.item item={item} />
        </div>
        <div :if={@running_turn} id="session-running" class="text-sm text-on-surface-variant">
          Codex is working…
        </div>
      </div>

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

      <form id="session-composer" phx-submit="send" phx-change="change" class="space-y-2">
        <textarea
          id="session-message"
          name="message"
          rows="3"
          class="textarea textarea-bordered w-full"
          placeholder={if @thread_id, do: "Reply to Codex…", else: "Ask Codex to do something…"}
          aria-label="Message"
          disabled={is_nil(@host)}
        >{@message}</textarea>
        <div class="flex justify-end gap-2">
          <.dm_btn :if={@running_turn} id="session-stop" type="button" phx-click="stop">
            Stop
          </.dm_btn>
          <.dm_btn
            id="session-send"
            native_submit
            type="submit"
            variant="primary"
            phx-disable-with="Sending…"
          >
            Send
          </.dm_btn>
        </div>
      </form>
    </section>
    """
  end
end
