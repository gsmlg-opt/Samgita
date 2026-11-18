defmodule SamgitaWeb.AgentsLive.Index do
  @moduledoc """
  Agent list and quick add.

  Codex is one kind of Agent: a Codex row shows its live app-server connection
  and can start, stop or reconnect it. Adding a Codex Agent asks only for a
  name and where Codex runs: this computer (its daemon socket) or another
  computer over SSH; everything else is adjusted later on the Agent page.
  """
  use SamgitaWeb, :live_view
  alias Samgita.{AgentIngress, Agents, CodexHosts, Management, Principal}
  alias SamgitaWeb.AgentsLive.Components

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Samgita.PubSub, CodexHosts.Runtime.topic())
      Phoenix.PubSub.subscribe(Samgita.PubSub, AgentIngress.topic())
    end

    {:ok,
     assign(socket,
       page_title: "Agents",
       form: new_form("codex"),
       error: nil,
       warning: nil,
       load_error: nil,
       hosts: %{},
       removal_commands: %{},
       ingress: %{pending: [], connected: %{}},
       pairing_forms: %{},
       ingress_error: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = assign(socket, offset: Components.offset(params))
    {:noreply, load(socket)}
  end

  @impl true
  def handle_event("change", %{"agent" => params}, socket) do
    previous = socket.assigns.form.params
    params = Map.merge(previous, params)

    # Changing what is being added requires a fresh duplicate check.
    params =
      if Map.take(params, ~w(kind location address)) !=
           Map.take(previous, ~w(kind location address)),
         do: Map.delete(params, "confirmed"),
         else: params

    {:noreply,
     assign(socket,
       form: to_form(params, as: :agent),
       error: nil,
       warning: if(params["confirmed"] == "true", do: socket.assigns.warning)
     )}
  end

  # One machine should be one Agent: probe the address first and ask for a
  # second confirmation when that machine or address is already configured.
  def handle_event(
        "add",
        %{"agent" => %{"kind" => "codex", "confirmed" => "true"} = params},
        socket
      ),
      do: add_codex(params, socket)

  def handle_event("add", %{"agent" => %{"kind" => "codex"} = params}, socket) do
    case CodexHosts.check_new(Principal.operator(), host_attrs(params)) do
      {:ok, %{"same_machine_as" => [_ | _] = same} = check} ->
        warning =
          "#{check["machine_name"] || machine(params)} is already added as " <>
            Enum.join(same, ", ") <>
            ". One machine should be one Agent. Add anyway only if this is intentional."

        {:noreply,
         assign(socket,
           form: to_form(Map.put(params, "confirmed", "true"), as: :agent),
           warning: warning,
           error: nil
         )}

      {:ok, _} ->
        add_codex(params, socket)

      {:error, error} ->
        {:noreply, failed(socket, params, error)}
    end
  end

  def handle_event("add", %{"agent" => params}, socket) do
    case register(params) do
      {:ok, agent} -> {:noreply, push_navigate(socket, to: ~p"/agents/#{agent["id"]}")}
      {:error, error} -> {:noreply, failed(socket, params, error)}
    end
  end

  def handle_event("pairing_change", %{"pairing" => params}, socket) do
    id = params["request_id"]

    case socket.assigns.pairing_forms[id] do
      nil ->
        {:noreply, socket}

      form ->
        selected_id = Map.get(params, "agent_id", form.params["agent_id"])

        values =
          if selected_id == form.params["agent_id"] do
            # Paging and status updates must not replace the reviewed version or command.
            form.params
          else
            selected = Enum.find(socket.assigns.page["data"], &(&1["id"] == selected_id))

            form.params
            |> Map.put("agent_id", selected_id)
            |> Map.put("selected_name", selected && selected["name"])
            |> Map.put("expected_version", selected && selected["version"])
            |> Map.put("command_id", Ecto.UUID.generate())
          end

        {:noreply,
         socket
         |> assign(:ingress_error, nil)
         |> update(:pairing_forms, &Map.put(&1, id, to_form(values, as: :pairing)))}
    end
  end

  def handle_event("approve_pairing", %{"pairing" => params}, socket) do
    attrs =
      params |> Map.take(~w(command_id agent_id expected_version)) |> Components.version_attrs()

    case AgentIngress.approve(Principal.operator(), params["request_id"], attrs) do
      {:ok, agent} ->
        {:noreply,
         socket
         |> load()
         |> assign(:ingress_error, nil)
         |> put_flash(
           :info,
           "#{agent["name"]} confirmed. This device can reconnect automatically."
         )}

      {:error, error} ->
        {:noreply, socket |> load() |> assign(:ingress_error, pairing_error(error))}
    end
  end

  def handle_event("reject_pairing", %{"id" => id}, socket) do
    case AgentIngress.reject(Principal.operator(), id) do
      :ok -> {:noreply, socket |> load() |> assign(:ingress_error, nil)}
      {:error, error} -> {:noreply, assign(socket, :ingress_error, pairing_error(error))}
    end
  end

  def handle_event("disconnect_inbound", %{"id" => id}, socket) do
    case AgentIngress.disconnect(Principal.operator(), id) do
      :ok ->
        {:noreply,
         socket
         |> load()
         |> put_flash(
           :info,
           "Connection closed. Revoke the device credential to prevent reconnecting."
         )}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Components.error_message(error))}
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

  def handle_event("remove", %{"id" => id} = params, socket) do
    attrs =
      %{"command_id" => params["command"], "expected_version" => params["version"]}
      |> Components.version_attrs()

    case Agents.remove(Principal.operator(), id, attrs) do
      {:ok, _} ->
        socket = socket |> load() |> put_flash(:info, "Agent removed. History is kept.")
        page = socket.assigns.page

        socket =
          if page["data"] == [] && page["offset"] > 0 do
            offset = div(max(page["total"] - 1, 0), 25) * 25
            push_patch(socket, to: ~p"/agents?offset=#{offset}")
          else
            socket
          end

        {:noreply, socket}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, removal_error(error))}
    end
  end

  # Status changes also update durable fields (generation, version), so reload.
  @impl true
  def handle_info({:codex_host_status, _id, _status}, socket), do: {:noreply, load(socket)}
  def handle_info({:agent_ingress_changed}, socket), do: {:noreply, load(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp add_codex(params, socket) do
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
       |> put_flash(:info, "#{agent["name"]} added. Connecting.")
       |> push_navigate(to: ~p"/agents")}
    else
      {:error, error} -> {:noreply, failed(socket, params, error)}
    end
  end

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

    endpoint =
      cond do
        params["connection_mode"] == "inbound_websocket" ->
          %{"transport" => "inbound_websocket"}

        address == "" ->
          %{}

        true ->
          %{"transport" => "websocket", "url" => address}
      end

    Agents.register(Principal.operator(), %{
      "command_id" => params["agent_command_id"],
      "name" => params["name"],
      "endpoint_metadata" => endpoint
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

  # This computer: the local Codex daemon's control socket. Another computer:
  # an SSH target (`host`, `user@host`, `host:port`) reached with the
  # operator's own SSH configuration, starting the Codex daemon there if needed.
  defp host_attrs(%{"location" => "ssh"} = params) do
    address = String.trim(params["address"] || "")

    if String.contains?(address, "://") and not String.starts_with?(address, "ssh://") do
      # Not an SSH target; fails validation.
      %{"transport" => "ssh", "ssh_host" => nil}
    else
      uri = URI.parse("ssh://" <> String.replace_prefix(address, "ssh://", ""))

      %{
        "transport" => "ssh",
        "ssh_host" => if(uri.path in [nil, ""], do: uri.host),
        "ssh_user" => uri.userinfo,
        "ssh_port" => uri.port,
        "use_ssh_config" => true,
        "ensure_daemon" => true
      }
    end
  end

  defp host_attrs(_params), do: %{"transport" => "local"}

  defp machine(%{"location" => "ssh", "address" => address}), do: address
  defp machine(_params), do: "This computer"

  defp failed(socket, params, error),
    do: assign(socket, form: to_form(params, as: :agent), error: Components.error_message(error))

  defp removal_error(%Samgita.Error{code: :conflict, details: %{reason: "unresolved_execution"}}),
    do: "This Agent has active or unresolved execution. Resolve it before removing the Agent."

  defp removal_error(error), do: Components.error_message(error)

  defp pairing_error(%Samgita.Error{code: :not_found}),
    do: gettext("This connection request expired or the device disconnected.")

  defp pairing_error(error), do: Components.error_message(error)

  defp load(socket) do
    with {:ok, page} <-
           Management.agents(Principal.operator(), %{
             "limit" => 25,
             "offset" => socket.assigns.offset
           }),
         {:ok, hosts} <- CodexHosts.list(Principal.operator()) do
      ingress = AgentIngress.snapshot()

      pairing_forms =
        Map.new(ingress.pending, fn request ->
          form =
            socket.assigns.pairing_forms[request.id] ||
              to_form(
                %{
                  "request_id" => request.id,
                  "command_id" => Ecto.UUID.generate(),
                  "agent_id" => "",
                  "expected_version" => nil
                },
                as: :pairing
              )

          {request.id, form}
        end)

      removal_commands =
        Map.new(page["data"], fn agent ->
          previous = socket.assigns.removal_commands[agent["id"]]

          command =
            if previous && previous.version == agent["version"],
              do: previous,
              else: %{id: Ecto.UUID.generate(), version: agent["version"]}

          {agent["id"], command}
        end)

      assign(socket,
        page: page,
        hosts: Map.new(hosts, &{&1["agent_id"], &1}),
        removal_commands: removal_commands,
        ingress: ingress,
        pairing_forms: pairing_forms,
        load_error: nil
      )
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
        "location" => "local",
        "address" => "",
        "connection_mode" => "websocket",
        "agent_command_id" => Ecto.UUID.generate(),
        "host_command_id" => Ecto.UUID.generate(),
        "enable_command_id" => Ecto.UUID.generate()
      },
      as: :agent
    )
  end

  @doc false
  def kind(agent), do: if(agent["runtime_driver"] == "codex", do: "Codex", else: "Agent")

  # A Codex Agent is shown by the machine it runs on, never by the local
  # forwarded ws:// address used to reach it.
  @doc false
  def address(nil, agent) do
    if inbound?(agent),
      do: gettext("Connects to Samgita"),
      else: agent["endpoint_metadata"]["url"] || "—"
  end

  def address(%{"machine_name" => name}, _) when is_binary(name), do: name
  def address(%{"transport" => "ssh", "ssh_host" => host}, _), do: host
  def address(%{"transport" => "local"}, _), do: "This computer"
  def address(_host, _), do: "Shown after connecting"

  @doc false
  def state(nil), do: nil
  def state(host), do: get_in(host, ["status", "state"]) || "stopped"

  @doc false
  def state_variant("connected"), do: "success"
  def state_variant(state) when state in ~w(connecting initializing backoff), do: "warning"
  def state_variant(_), do: "neutral"

  @doc false
  def inbound?(agent),
    do: get_in(agent, ["endpoint_metadata", "transport"]) == "inbound_websocket"

  @doc false
  def inbound_state(agent, connected) do
    cond do
      !agent["enabled"] -> "disabled"
      connection = connected[agent["id"]] -> to_string(connection.state)
      true -> "offline"
    end
  end

  @doc false
  def pairing_options(agents, selected_params \\ %{}) do
    existing =
      agents
      |> Enum.filter(&(&1["enabled"] && !&1["removed_at"] && &1["runtime_driver"] != "codex"))
      |> Enum.map(&{&1["name"], &1["id"]})

    selected_id = selected_params["agent_id"]

    existing =
      if is_binary(selected_id) && selected_id != "" &&
           !Enum.any?(existing, fn {_name, id} -> id == selected_id end) do
        label = selected_params["selected_name"] || gettext("Selected Agent")
        [{label <> " (" <> selected_id <> ")", selected_id} | existing]
      else
        existing
      end

    [{gettext("Create a new Agent"), ""} | existing]
  end
end
