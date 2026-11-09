defmodule SamgitaWeb.SessionsLive.Items do
  @moduledoc """
  Folds Codex thread items and live notifications into the rows a session page
  renders, and the components for those rows. Unknown item types render as a
  short label; their contents are never interpreted.
  """
  use Phoenix.Component
  import PhoenixDuskmoon.Component.Icon.Icons

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

  attr :item, :map, required: true

  def item(%{item: %{"kind" => "user"}} = assigns) do
    ~H"""
    <div class="flex justify-end">
      <p
        class="max-w-[80%] whitespace-pre-wrap rounded-xl bg-surface-container-high px-4 py-2"
        phx-no-format
      >{@item["text"]}</p>
    </div>
    """
  end

  def item(%{item: %{"kind" => kind}} = assigns) when kind in ["agent", "plan"] do
    ~H"""
    <p class="whitespace-pre-wrap" phx-no-format>{@item["text"]}</p>
    """
  end

  def item(%{item: %{"kind" => "reasoning"}} = assigns) do
    ~H"""
    <p
      :if={@item["text"] not in [nil, ""]}
      class="whitespace-pre-wrap text-sm italic text-on-surface-variant"
      phx-no-format
    >{@item["text"]}</p>
    """
  end

  def item(%{item: %{"kind" => "command"}} = assigns) do
    ~H"""
    <details class="rounded-lg border border-outline-variant">
      <summary class="flex cursor-pointer items-center gap-2 px-3 py-2 font-mono text-sm">
        <.dm_mdi name="console" class="h-4 w-4 shrink-0" />
        <span class="truncate">{@item["command"]}</span>
        <span class="ml-auto shrink-0 text-xs text-on-surface-variant">
          {@item["status"]}{if @item["exit_code"], do: " · exit #{@item["exit_code"]}"}
        </span>
      </summary>
      <pre
        :if={@item["output"] not in [nil, ""]}
        class="max-h-80 overflow-auto whitespace-pre-wrap border-t border-outline-variant px-3 py-2 text-xs"
      >{@item["output"]}</pre>
    </details>
    """
  end

  def item(%{item: %{"kind" => "file_change"}} = assigns) do
    ~H"""
    <div class="rounded-lg border border-outline-variant px-3 py-2 text-sm">
      <div class="flex items-center gap-2">
        <.dm_mdi name="file-document-edit-outline" class="h-4 w-4" />
        <span>Edited files</span>
        <span class="ml-auto text-xs text-on-surface-variant">{@item["status"]}</span>
      </div>
      <code :for={path <- @item["paths"]} class="block break-all text-xs">{path}</code>
    </div>
    """
  end

  def item(assigns) do
    ~H"""
    <p class="text-xs text-on-surface-variant">{@item["label"]}</p>
    """
  end

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
