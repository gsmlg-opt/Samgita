defmodule SamgitaWeb.SessionsLive.Items do
  @moduledoc """
  Folds Codex thread items and live notifications into the rows a session page
  renders with the DuskMoon chat elements (`@duskmoon-dev/el-chat`). Unknown
  item types render as a short label; their contents are never interpreted.
  """
  use Phoenix.Component

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
  the last reply forms a reply that has no text yet.
  """
  def rows(items) do
    {rows, work} =
      Enum.reduce(items, {[], []}, fn
        %{"kind" => "user"} = item, {rows, work} ->
          {[%{kind: :user, item: item} | flush(rows, work)], []}

        %{"kind" => "agent"} = item, {rows, work} ->
          {[%{kind: :agent, id: item["id"], text: item["text"], work: Enum.reverse(work)} | rows],
           []}

        item, {rows, work} ->
          {rows, [item | work]}
      end)

    rows |> flush(work) |> Enum.reverse()
  end

  defp flush(rows, []), do: rows

  defp flush(rows, work) do
    work = Enum.reverse(work)
    [%{kind: :agent, id: "work-" <> hd(work)["id"], text: nil, work: work} | rows]
  end

  attr :row, :map, required: true
  attr :streaming, :boolean, default: false

  def row(%{row: %{kind: :user}} = assigns) do
    ~H"""
    <el-dm-chat
      id={"item-" <> @row.item["id"]}
      align="end"
      collapsible
      content={@row.item["text"]}
    >
    </el-dm-chat>
    """
  end

  def row(assigns) do
    ~H"""
    <el-dm-chat id={"item-" <> @row.id} agent streaming={@streaming} content={@row.text || ""}>
      <el-dm-chat-work :if={@row.work != []} slot="work" summary={work_summary(@row.work)}>
        <.work :for={item <- @row.work} item={item} />
      </el-dm-chat-work>
    </el-dm-chat>
    """
  end

  defp work_summary(work) do
    case length(work) do
      1 -> "Worked · 1 step"
      n -> "Worked · #{n} steps"
    end
  end

  attr :item, :map, required: true

  defp work(%{item: %{"kind" => "command"}} = assigns) do
    ~H"""
    <el-dm-chat-tool
      id={"item-" <> @item["id"]}
      name={@item["command"]}
      status={tool_status(@item)}
    >
      <div slot="result">
        <p :if={@item["exit_code"]} class="text-xs text-on-surface-variant">
          exit {@item["exit_code"]}
        </p>
        <pre
          :if={@item["output"] not in [nil, ""]}
          class="max-h-80 overflow-auto whitespace-pre-wrap text-xs"
        >{@item["output"]}</pre>
      </div>
    </el-dm-chat-tool>
    """
  end

  defp work(%{item: %{"kind" => "file_change"}} = assigns) do
    ~H"""
    <el-dm-chat-tool id={"item-" <> @item["id"]} name="Edited files" status={tool_status(@item)}>
      <div slot="result">
        <code :for={path <- @item["paths"]} class="block break-all text-xs">{path}</code>
      </div>
    </el-dm-chat-tool>
    """
  end

  defp work(%{item: %{"kind" => kind}} = assigns) when kind in ["reasoning", "plan"] do
    ~H"""
    <el-dm-chat-reasoning
      :if={@item["text"] not in [nil, ""]}
      id={"item-" <> @item["id"]}
      summary={if @item["kind"] == "plan", do: "Plan", else: "Reasoning"}
    >
      <p class="whitespace-pre-wrap" phx-no-format>{@item["text"]}</p>
    </el-dm-chat-reasoning>
    """
  end

  defp work(assigns) do
    ~H"""
    <el-dm-chat-tool id={"item-" <> @item["id"]} name={@item["label"]} status="success">
    </el-dm-chat-tool>
    """
  end

  # Codex item status -> el-dm-chat-tool status.
  defp tool_status(%{"status" => "inProgress"}), do: "running"

  defp tool_status(%{"status" => "completed", "exit_code" => code}) when code not in [nil, 0],
    do: "error"

  defp tool_status(%{"status" => "completed"}), do: "success"
  defp tool_status(%{"status" => status}) when status in ["failed", "declined"], do: "error"
  defp tool_status(_), do: "pending"

  attr :request, :map, required: true

  def request(%{request: %{"method" => "item/commandExecution/requestApproval"}} = assigns) do
    ~H"""
    <p class="font-semibold">Codex wants to run a command</p>
    <code class="mt-2 block whitespace-pre-wrap break-all text-sm">{@request["params"]["command"]}</code>
    <p :if={@request["params"]["reason"]} class="mt-1 text-sm text-on-surface-variant">
      {@request["params"]["reason"]}
    </p>
    """
  end

  def request(%{request: %{"method" => "item/fileChange/requestApproval"}} = assigns) do
    ~H"""
    <p class="font-semibold">Codex wants to change files</p>
    <p :if={@request["params"]["reason"]} class="mt-1 text-sm text-on-surface-variant">
      {@request["params"]["reason"]}
    </p>
    """
  end

  def request(assigns) do
    ~H"""
    <p class="font-semibold">Codex is asking for permission</p>
    <p class="text-sm text-on-surface-variant">{@request["method"]}</p>
    """
  end
end
