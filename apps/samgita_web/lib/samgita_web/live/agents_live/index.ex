defmodule SamgitaWeb.AgentsLive.Index do
  @moduledoc """
  Agent list and quick add.

  Codex is one kind of Agent: a Codex row shows its live app-server connection
  and can start, stop or reconnect it. Adding asks only for the kind, a name and
  an address; everything else is adjusted later on the Agent page.
  """
  use SamgitaWeb, :live_view
  alias Samgita.{Agents, CodexHosts, Management, Principal}
  alias SamgitaWeb.AgentsLive.Components

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(Samgita.PubSub, CodexHosts.Runtime.topic())

    {:ok,
     assign(socket,
       page_title: "Agents",
       form: new_form("codex"),
       error: nil,
       load_error: nil,
       hosts: %{}
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = assign(socket, offset: Components.offset(params))
    {:noreply, load(socket)}
  end

  @impl true
  def handle_event("change", %{"agent" => params}, socket) do
    params = Map.merge(socket.assigns.form.params, params)

    params =
      if params["kind"] != socket.assigns.form.params["kind"],
        do: Map.put(params, "address", default_address(params["kind"])),
        else: params

    {:noreply, assign(socket, form: to_form(params, as: :agent), error: nil)}
  end

  def handle_event("add", %{"agent" => %{"kind" => "codex"} = params}, socket) do
    # Three commands with stable command IDs: a retry after a partial failure
    # replays the completed steps from their receipts.
    with :ok <- CodexHosts.validate_settings(host_attrs(params)),
         {:ok, agent} <- register(params),
         {:ok, host} <- configure(agent, params),
         {:ok, _} <-
           CodexHosts.enable(Principal.operator(), host["id"], %{
             "command_id" => params["enable_command_id"],
             "expected_version" => host["version"]
           }) do
      # Navigating back resets the page, which also closes the dialog.
      {:noreply,
       socket
       |> put_flash(:info, "#{agent["name"]} added. Connecting to #{params["address"]}.")
       |> push_navigate(to: ~p"/agents")}
    else
      {:error, error} -> {:noreply, failed(socket, params, error)}
    end
  end

  def handle_event("add", %{"agent" => params}, socket) do
    case register(params) do
      {:ok, agent} -> {:noreply, push_navigate(socket, to: ~p"/agents/#{agent["id"]}")}
      {:error, error} -> {:noreply, failed(socket, params, error)}
    end
  end

  def handle_event(event, %{"id" => id}, socket) when event in ~w(start stop) do
    host = Enum.find_value(socket.assigns.hosts, fn {_, h} -> h["id"] == id && h end)
    fun = if event == "start", do: &CodexHosts.enable/3, else: &CodexHosts.disable/3
    attrs = %{"command_id" => Ecto.UUID.generate(), "expected_version" => host && host["version"]}

    case host && fun.(Principal.operator(), id, attrs) do
      {:error, error} ->
        {:noreply, socket |> load() |> put_flash(:error, Components.error_message(error))}

      _ ->
        {:noreply, load(socket)}
    end
  end

  def handle_event("reconnect", %{"id" => id}, socket) do
    case CodexHosts.reconnect(Principal.operator(), id) do
      :ok -> {:noreply, put_flash(socket, :info, "Reconnecting.")}
      _ -> {:noreply, socket |> load() |> put_flash(:error, "The connection is not running.")}
    end
  end

  # Status changes also update durable fields (generation, version), so reload.
  @impl true
  def handle_info({:codex_host_status, _id, _status}, socket), do: {:noreply, load(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp register(%{"kind" => "codex"} = params) do
    Agents.register(Principal.operator(), %{
      "command_id" => params["agent_command_id"],
      "name" => params["name"],
      "implementation" => "codex",
      "runtime_driver" => "codex",
      # Codex is not pinned; the connection records the version it reports.
      "runtime_version" => SamgitaProtocolCodex.source()["version"]
    })
  end

  defp register(params) do
    address = String.trim(params["address"] || "")

    Agents.register(Principal.operator(), %{
      "command_id" => params["agent_command_id"],
      "name" => params["name"],
      "endpoint_metadata" =>
        if(address == "", do: %{}, else: %{"transport" => "websocket", "url" => address})
    })
  end

  defp configure(agent, params) do
    CodexHosts.configure(
      Principal.operator(),
      Map.merge(host_attrs(params), %{
        "command_id" => params["host_command_id"],
        "agent_id" => agent["id"]
      })
    )
  end

  defp host_attrs(params),
    do: %{"transport" => "websocket", "url" => String.trim(params["address"] || "")}

  defp failed(socket, params, error),
    do: assign(socket, form: to_form(params, as: :agent), error: Components.error_message(error))

  defp load(socket) do
    with {:ok, page} <-
           Management.agents(Principal.operator(), %{
             "limit" => 25,
             "offset" => socket.assigns.offset
           }),
         {:ok, hosts} <- CodexHosts.list(Principal.operator()) do
      assign(socket, page: page, hosts: Map.new(hosts, &{&1["agent_id"], &1}), load_error: nil)
    else
      {:error, error} ->
        assign(socket,
          page: %{"data" => [], "offset" => 0, "limit" => 25, "total" => 0},
          load_error: Components.error_message(error)
        )
    end
  end

  defp new_form(kind) do
    to_form(
      %{
        "kind" => kind,
        "name" => "",
        "address" => default_address(kind),
        "agent_command_id" => Ecto.UUID.generate(),
        "host_command_id" => Ecto.UUID.generate(),
        "enable_command_id" => Ecto.UUID.generate()
      },
      as: :agent
    )
  end

  defp default_address("codex"), do: "ws://127.0.0.1:47811"
  defp default_address(_), do: ""

  @doc false
  def kind(agent), do: if(agent["runtime_driver"] == "codex", do: "Codex", else: "Agent")

  @doc false
  def state(nil), do: nil
  def state(host), do: get_in(host, ["status", "state"]) || "stopped"

  @doc false
  def state_variant("connected"), do: "success"
  def state_variant(state) when state in ~w(connecting backoff), do: "warning"
  def state_variant(_), do: "neutral"
end
