defmodule SamgitaWeb.SessionsLive.Items do
  @moduledoc """
  Folds Codex thread items and live notifications into the rows a session page
  renders with the DuskMoon React chat. Unknown item types render as a short
  label; their contents are never interpreted.
  """

  @doc "Rows from the turns returned by `thread/resume`."
  def from_turns(turns) do
    for turn <- List.wrap(turns),
        item <- List.wrap(turn["items"]),
        row = normalize(item),
        row != nil,
        do: row
  end

  @doc "The ID of a turn that is still running, if any."
  def running_turn(turns) do
    turns
    |> List.wrap()
    |> Enum.find_value(fn turn -> turn["status"] == "inProgress" && turn["id"] end)
  end

  @doc "Request kinds this page can answer with the Codex approval decisions."
  def answerable?(%{"method" => method}),
    do: method in ["item/commandExecution/requestApproval", "item/fileChange/requestApproval"]

  def answerable?(_), do: false

  @doc "Apply one live notification of the thread to the socket assigns."
  def apply_event(socket, %{"method" => method, "params" => params}) do
    case method do
      "turn/started" ->
        Phoenix.Component.assign(socket, running_turn: get_in(params, ["turn", "id"]))

      "turn/completed" ->
        error = get_in(params, ["turn", "error", "message"])

        Phoenix.Component.assign(socket,
          running_turn: nil,
          error: if(error, do: "Codex stopped: " <> error, else: socket.assigns.error)
        )

      m when m in ["item/started", "item/completed"] ->
        upsert(socket, normalize(params["item"]))

      "item/agentMessage/delta" ->
        append(socket, params["itemId"], "text", params["delta"], %{"kind" => "agent"})

      "item/commandExecution/outputDelta" ->
        append(socket, params["itemId"], "output", params["delta"], %{"kind" => "command"})

      "thread/name/updated" ->
        Phoenix.Component.assign(socket, title: params["threadName"] || socket.assigns.title)

      _ ->
        socket
    end
  end

  def apply_event(socket, _wire), do: socket

  defp upsert(socket, %{"id" => id} = item) do
    items = socket.assigns.items

    items =
      if Enum.any?(items, &(&1["id"] == id)),
        do:
          Enum.map(items, fn
            %{"id" => ^id} = old -> merge(old, item)
            other -> other
          end),
        else: items ++ [item]

    Phoenix.Component.assign(socket, items: items)
  end

  defp upsert(socket, _item), do: socket

  # A completed item replaces the streamed text unless it carries none.
  defp merge(old, new),
    do:
      Map.merge(old, new, fn _key, previous, next ->
        if next in [nil, ""], do: previous, else: next
      end)

  defp append(socket, id, field, delta, base) when is_binary(id) and is_binary(delta) do
    items = socket.assigns.items

    items =
      if Enum.any?(items, &(&1["id"] == id)),
        do:
          Enum.map(items, fn
            %{"id" => ^id} = item -> Map.update(item, field, delta, &((&1 || "") <> delta))
            other -> other
          end),
        else: items ++ [Map.merge(base, %{"id" => id, field => delta})]

    Phoenix.Component.assign(socket, items: items)
  end

  defp append(socket, _id, _field, _delta, _base), do: socket

  @doc false
  def normalize(%{"type" => "userMessage", "id" => id} = item),
    do: %{
      "id" => id,
      "kind" => "user",
      "text" =>
        item["content"]
        |> List.wrap()
        |> Enum.map_join("\n", fn
          %{"type" => "text", "text" => text} -> text
          %{"type" => type} -> "[#{type}]"
          _ -> ""
        end)
    }

  def normalize(%{"type" => "agentMessage", "id" => id} = item),
    do: %{"id" => id, "kind" => "agent", "text" => item["text"]}

  def normalize(%{"type" => "plan", "id" => id} = item),
    do: %{"id" => id, "kind" => "plan", "text" => item["text"]}

  def normalize(%{"type" => "reasoning", "id" => id} = item),
    do: %{
      "id" => id,
      "kind" => "reasoning",
      "text" => item["summary"] |> List.wrap() |> Enum.filter(&is_binary/1) |> Enum.join("\n")
    }

  def normalize(%{"type" => "commandExecution", "id" => id} = item),
    do: %{
      "id" => id,
      "kind" => "command",
      "command" => item["command"],
      "status" => item["status"],
      "output" => item["aggregatedOutput"],
      "exit_code" => item["exitCode"]
    }

  def normalize(%{"type" => "fileChange", "id" => id} = item),
    do: %{
      "id" => id,
      "kind" => "file_change",
      "status" => item["status"],
      "paths" => for(%{"path" => path} <- List.wrap(item["changes"]), do: path)
    }

  def normalize(%{"type" => type, "id" => id}),
    do: %{"id" => id, "kind" => "other", "label" => type}

  def normalize(_), do: nil

  @doc """
  Group items into chat rows: each user message, and each Codex reply with the
  work (commands, file changes, reasoning, plans) done before it. Work after
  the last reply forms a reply that has no text yet. A reply is identified by
  its first item, so its ID does not change when its text arrives later.
  """
  def rows(items) do
    {rows, work} =
      Enum.reduce(items, {[], []}, fn
        %{"kind" => "user"} = item, {rows, work} ->
          {[%{kind: :user, item: item} | flush(rows, work)], []}

        %{"kind" => "agent"} = item, {rows, work} ->
          work = Enum.reverse(work)
          id = if work == [], do: item["id"], else: hd(work)["id"]
          {[%{kind: :agent, id: id, text: item["text"], work: work} | rows], []}

        item, {rows, work} ->
          {rows, [item | work]}
      end)

    rows |> flush(work) |> Enum.reverse()
  end

  defp flush(rows, []), do: rows

  defp flush(rows, work) do
    work = Enum.reverse(work)
    [%{kind: :agent, id: hd(work)["id"], text: nil, work: work} | rows]
  end

  @doc """
  The messages of the DuskMoon React chat (`dm_react_chat`). The last Codex
  reply is streaming while a turn runs; Codex's work is shown as its tools.
  Pending Codex requests belong to the running turn, so they are shown in the
  last reply, or in a reply of their own when Codex has not replied yet.
  """
  def messages(items, running?, requests \\ []) do
    rows = rows(items)
    last = length(rows) - 1

    rows
    |> Enum.with_index()
    |> Enum.map(fn
      {%{kind: :user, item: item}, _} ->
        %{
          "id" => item["id"],
          "role" => "user",
          "author" => "You",
          "content" => item["text"] || "",
          "status" => "complete"
        }

      {row, index} ->
        %{
          "id" => row.id,
          "role" => "assistant",
          "author" => "Codex",
          "content" => row.text || "",
          "status" => if(running? and index == last, do: "streaming", else: "complete"),
          "tools" => for(item <- row.work, shown?(item), do: tool(item))
        }
    end)
    |> with_requests(Enum.map(requests, &request/1))
  end

  defp with_requests(messages, []), do: messages

  defp with_requests(messages, requests) do
    case List.last(messages) do
      %{"role" => "assistant"} = reply ->
        List.replace_at(messages, -1, Map.put(reply, "requests", requests))

      _ ->
        messages ++
          [
            %{
              "id" => "requests",
              "role" => "assistant",
              "author" => "Codex",
              "content" => "",
              "status" => "complete",
              "tools" => [],
              "requests" => requests
            }
          ]
    end
  end

  # Reasoning often has no summary text; an empty entry says nothing.
  defp shown?(%{"kind" => kind, "text" => text}) when kind in ["reasoning", "plan"],
    do: text not in [nil, ""]

  defp shown?(_item), do: true

  # Rendered by `assets/js/session_chat.js` by kind: commands with their exit
  # code and output, file changes with their paths, reasoning and plans as text.
  defp tool(%{"kind" => "command"} = item),
    do: %{
      "id" => item["id"],
      "kind" => "command",
      "name" => item["command"],
      "status" => tool_status(item),
      "result" =>
        if(item["status"] != "inProgress",
          do: %{"exit_code" => item["exit_code"], "output" => item["output"]}
        )
    }

  defp tool(%{"kind" => "file_change"} = item),
    do: %{
      "id" => item["id"],
      "kind" => "file_change",
      "name" => "Edited files",
      "status" => tool_status(item),
      "paths" => item["paths"]
    }

  defp tool(%{"kind" => kind} = item) when kind in ["reasoning", "plan"],
    do: %{
      "id" => item["id"],
      "kind" => kind,
      "name" => if(kind == "plan", do: "Plan", else: "Reasoning"),
      "status" => "success",
      "text" => item["text"]
    }

  defp tool(item),
    do: %{"id" => item["id"], "kind" => "other", "name" => item["label"], "status" => "success"}

  # Codex item status -> chat tool status.
  defp tool_status(%{"status" => "inProgress"}), do: "running"

  defp tool_status(%{"status" => "completed", "exit_code" => code}) when code not in [nil, 0],
    do: "error"

  defp tool_status(%{"status" => "completed"}), do: "success"
  defp tool_status(%{"status" => status}) when status in ["failed", "declined"], do: "error"
  defp tool_status(_), do: "pending"

  # A pending Codex request as the chat shows it (`Chat.Request` in
  # `assets/js/session_chat.js`): what Codex asks for and whether this page
  # can answer it.
  defp request(%{"method" => "item/commandExecution/requestApproval"} = request),
    do: request(request, "Codex wants to run a command", request["params"]["command"])

  defp request(%{"method" => "item/fileChange/requestApproval"} = request),
    do: request(request, "Codex wants to change files", nil)

  defp request(request), do: request(request, "Codex is asking for permission", nil)

  defp request(request, title, command),
    do: %{
      "key" => request["key"],
      "title" => title,
      "command" => command,
      "reason" => get_in(request, ["params", "reason"]),
      "method" => request["method"],
      "answerable" => answerable?(request)
    }
end
