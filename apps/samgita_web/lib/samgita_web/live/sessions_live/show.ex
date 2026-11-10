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

    # Connection state of the host drives the composer's status dot.
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(Samgita.PubSub, CodexHosts.Runtime.topic())

    socket =
      if connected?(socket) and host,
        do:
          start_async(socket, :models, fn -> CodexHosts.models(Principal.operator(), host_id) end),
        else: socket

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
       settings: nil,
       # Model, effort and access chosen in the composer, applied by the next
       # turn start (and then kept by Codex for later turns).
       pending: %{},
       models: [],
       settings_revision: 0,
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
             socket.assigns.running_turn,
             if(socket.assigns.running_turn, do: %{}, else: socket.assigns.pending)
           ) do
      socket =
        socket
        |> applied()
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

  # A composer setting (access, model, reasoning effort) chosen for the next turn.
  def handle_event("chat.setting", %{"settingId" => id, "value" => value}, socket) do
    if Enum.any?(composer_settings(socket.assigns), fn setting ->
         setting.id == id and Enum.any?(setting.choices, &(&1.value == value))
       end) do
      socket =
        socket
        |> update(:pending, &choose(&1, id, value, socket.assigns))
        |> update(:settings_revision, &(&1 + 1))
        |> snapshot()

      {:reply, %{status: "ok", revision: socket.assigns.settings_revision, value: value}, socket}
    else
      {:reply, %{status: "error", message: "This choice is not available."}, socket}
    end
  end

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

  def handle_info({:codex_host_status, id, status}, %{assigns: %{host_id: id}} = socket),
    do: {:noreply, socket |> update(:host, &(&1 && Map.put(&1, "status", status))) |> snapshot()}

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
       settings: thread["settings"],
       requests: requests
     )
     |> snapshot()}
  end

  def handle_async(:models, {:ok, {:ok, models}}, socket),
    do: {:noreply, socket |> assign(models: models) |> snapshot()}

  def handle_async(:models, _result, socket), do: {:noreply, socket}

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
          admission: admission(socket),
          metadata: metadata(socket.assigns)
        })
      )

  @doc false
  # The composer's context, as in the Codex app: project, where Codex runs and
  # whether it is connected, and the access, model and reasoning settings that
  # the next message will use.
  def metadata(assigns) do
    host = assigns.host || %{}
    current = current(assigns)

    %{
      project: assigns.cwd && Path.basename(assigns.cwd),
      host: host["machine_name"] || host["agent_name"],
      location: if(host["transport"] == "local", do: "Local", else: "Remote"),
      connected: get_in(host, ["status", "state"]) == "connected",
      model: current["model"],
      effort: current["effort"],
      access: current["access"],
      full_access: current["access"] == "full",
      settings_revision: assigns.settings_revision,
      settings: composer_settings(assigns),
      # Chosen but not yet applied: takes effect with the next message.
      pending: assigns.pending != %{}
    }
  end

  @access_choices [
    {"read_only", "Read only"},
    {"default", "Default access"},
    {"full", "Full access"}
  ]

  # What the session uses now (reported by Codex), overlaid with pending choices.
  defp current(assigns) do
    settings = assigns.settings || %{}
    default = Enum.find(assigns.models, & &1["default"]) || %{}

    Map.merge(
      %{
        "access" => CodexHosts.access_mode(settings["sandbox"]),
        "model" => settings["model"] || default["id"],
        "effort" => settings["reasoning_effort"] || default["default_effort"]
      },
      assigns.pending
    )
  end

  defp composer_settings(assigns) do
    current = current(assigns)
    model = Enum.find(assigns.models, &(&1["id"] == current["model"]))

    models =
      for(m <- assigns.models, do: %{value: m["id"], label: m["name"]})
      |> with_current(current["model"])

    efforts =
      for(e <- (model && model["efforts"]) || [], do: %{value: e, label: e})
      |> with_current(current["effort"])

    [
      %{
        id: "access",
        label: "Access",
        value: current["access"],
        choices: for({value, label} <- @access_choices, do: %{value: value, label: label})
      },
      %{id: "model", label: "Model", value: current["model"] || "", choices: models},
      %{id: "effort", label: "Reasoning", value: current["effort"] || "", choices: efforts}
    ]
  end

  # The value in use stays selectable even when the list does not offer it.
  defp with_current(choices, nil), do: choices

  defp with_current(choices, value),
    do:
      if(Enum.any?(choices, &(&1.value == value)),
        do: choices,
        else: [%{value: value, label: value} | choices]
      )

  # A new model is sent with the effort shown for it: the current effort when
  # the model supports it, otherwise the model's default.
  defp choose(pending, "model", value, assigns) do
    model = Enum.find(assigns.models, &(&1["id"] == value)) || %{}
    effort = current(assigns)["effort"]

    effort =
      if effort in List.wrap(model["efforts"]), do: effort, else: model["default_effort"]

    pending
    |> Map.put("model", value)
    |> put_present("effort", effort)
  end

  defp choose(pending, id, value, _assigns), do: Map.put(pending, id, value)

  # After a turn starts with the pending choices, Codex keeps them.
  defp applied(%{assigns: %{pending: pending}} = socket) when pending == %{}, do: socket

  defp applied(%{assigns: %{running_turn: nil, pending: pending}} = socket) do
    sandbox =
      case pending["access"] do
        "read_only" -> "readOnly"
        "full" -> "dangerFullAccess"
        "default" -> "workspaceWrite"
        nil -> nil
      end

    settings =
      (socket.assigns.settings || %{})
      |> put_present("model", pending["model"])
      |> put_present("reasoning_effort", pending["effort"])
      |> put_present("sandbox", sandbox)

    assign(socket, settings: settings, pending: %{})
  end

  defp applied(socket), do: socket

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

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
          |> assign(
            thread_id: thread["id"],
            title: thread["title"] || socket.assigns.title,
            settings: thread["settings"]
          )
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
        metadata={metadata(assigns)}
        actions={%{setting: "chat.setting"}}
        admission={%{canSubmit: @host != nil, allowWhileStreaming: true}}
        class="block h-[calc(100dvh-14rem)] min-h-96"
      />
    </section>
    """
  end
end
