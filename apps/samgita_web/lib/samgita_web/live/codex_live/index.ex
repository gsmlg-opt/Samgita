defmodule SamgitaWeb.CodexLive.Index do
  @moduledoc """
  Operator overview of Codex app-server connections (design §11).

  Lists every configured Codex host with its live connection state, starts and
  stops a connection (enable/disable) and adds a WebSocket host, such as a local
  `codex app-server --listen ws://127.0.0.1:47811` or another machine's
  app-server forwarded to a local port over SSH. Samgita never starts or stops
  the Codex process itself.
  """
  use SamgitaWeb, :live_view
  alias Samgita.{Agents, CodexHosts, Principal}
  alias SamgitaWeb.AgentsLive.Components

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(Samgita.PubSub, CodexHosts.Runtime.topic())

    {:ok,
     socket
     |> assign(page_title: "Codex", error: nil, form: new_form())
     |> load()}
  end

  @impl true
  def handle_event("change", %{"codex" => params}, socket),
    do: {:noreply, assign(socket, form: to_form(params, as: :codex), error: nil)}

  # Three commands with stable command IDs: a retry after a partial failure
  # replays the completed steps from their receipts.
  def handle_event("add", %{"codex" => params}, socket) do
    with :ok <- CodexHosts.validate_settings(host_attrs(params)),
         {:ok, agent} <- register(params),
         {:ok, host} <- configure(agent, params),
         {:ok, _} <-
           CodexHosts.enable(
             Principal.operator(),
             host["id"],
             %{"command_id" => params["enable_command_id"], "expected_version" => host["version"]}
           ) do
      {:noreply,
       socket
       |> assign(form: new_form(), error: nil)
       |> load()
       |> put_flash(:info, "Codex added. Samgita is connecting to #{params["url"]}.")}
    else
      {:error, error} ->
        {:noreply,
         assign(socket,
           form: to_form(params, as: :codex),
           error: Components.error_message(error)
         )}
    end
  end

  def handle_event(event, %{"id" => id}, socket) when event in ~w(start stop) do
    host = Enum.find(socket.assigns.hosts, &(&1["id"] == id))
    fun = if event == "start", do: &CodexHosts.enable/3, else: &CodexHosts.disable/3

    attrs = %{"command_id" => Ecto.UUID.generate(), "expected_version" => host && host["version"]}

    case host && fun.(Principal.operator(), id, attrs) do
      {:ok, _} ->
        {:noreply, load(socket)}

      {:error, error} ->
        {:noreply, socket |> load() |> put_flash(:error, Components.error_message(error))}

      nil ->
        {:noreply, load(socket)}
    end
  end

  def handle_event("reconnect", %{"id" => id}, socket) do
    case CodexHosts.reconnect(Principal.operator(), id) do
      :ok -> {:noreply, put_flash(socket, :info, "Reconnecting.")}
      _ -> {:noreply, socket |> load() |> put_flash(:error, "The connection is not running.")}
    end
  end

  @impl true
  # Status changes also update durable fields (generation, version), so reload.
  def handle_info({:codex_host_status, _id, _status}, socket), do: {:noreply, load(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp register(params) do
    Agents.register(Principal.operator(), %{
      "command_id" => params["agent_command_id"],
      "name" => params["name"],
      "implementation" => "codex",
      "runtime_driver" => "codex",
      "runtime_version" => params["version"]
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
    do: %{
      "transport" => "websocket",
      "url" => params["url"],
      "token_ref" => blank_to_nil(params["token_ref"])
    }

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: String.trim(value)

  defp load(socket) do
    {:ok, hosts} = CodexHosts.list(Principal.operator())
    assign(socket, hosts: hosts)
  end

  defp new_form do
    to_form(
      %{
        "name" => "",
        "url" => "ws://127.0.0.1:47811",
        "version" => SamgitaProtocolCodex.source()["version"],
        "token_ref" => "",
        "agent_command_id" => Ecto.UUID.generate(),
        "host_command_id" => Ecto.UUID.generate(),
        "enable_command_id" => Ecto.UUID.generate()
      },
      as: :codex
    )
  end

  defp endpoint(%{"transport" => "ssh"} = host), do: "ssh #{host["ssh_host"]}"
  defp endpoint(host), do: host["url"]

  defp timestamp(nil), do: gettext("Never")

  defp timestamp(%DateTime{} = time), do: Calendar.strftime(time, "%Y-%m-%d %H:%M:%S UTC")

  defp timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _} -> timestamp(time)
      _ -> value
    end
  end

  defp state(host), do: get_in(host, ["status", "state"]) || "stopped"

  defp state_variant("connected"), do: "success"
  defp state_variant(state) when state in ~w(connecting backoff), do: "warning"
  defp state_variant("failed"), do: "error"
  defp state_variant(_), do: "neutral"

  @impl true
  def render(assigns) do
    ~H"""
    <section class="space-y-6" aria-labelledby="codex-title">
      <header>
        <h1 id="codex-title" class="text-3xl font-bold">{gettext("Codex")}</h1>
        <p class="text-on-surface-variant">
          {gettext(
            "Codex app-server connections. Run `codex app-server --listen ws://127.0.0.1:PORT` on each machine and forward remote ports over SSH; Samgita connects, reports state and starts or stops the connection, never the Codex process."
          )}
        </p>
      </header>
      <.dm_card variant="bordered">
        <:title>{gettext("Connections")}</:title>
        <p :if={@hosts == []} id="codex-empty">
          {gettext("No Codex connections yet. Add one below.")}
        </p>
        <div :if={@hosts != []} class="overflow-x-auto">
          <.dm_table id="codex-hosts" data={@hosts}>
            <:col :let={host} label={gettext("Codex")}>
              <.dm_link navigate={~p"/agents/#{host["agent_id"]}"}>{host["agent_name"]}</.dm_link>
            </:col>
            <:col :let={host} label={gettext("Endpoint")}>
              <code class="break-all">{endpoint(host)}</code>
            </:col>
            <:col :let={host} label={gettext("State")}>
              <.dm_badge variant={state_variant(state(host))} class="codex-state">
                {state(host)}
              </.dm_badge>
              <span :if={host["status"]["error"]} class="block text-xs text-error">
                {host["status"]["error"]}
              </span>
            </:col>
            <:col :let={host} label={gettext("Version")}>{host["server_version"] || "—"}</:col>
            <:col :let={host} label={gettext("Generation")}>{host["generation"]}</:col>
            <:col :let={host} label={gettext("Last connected")}>
              {timestamp(host["last_connected_at"])}
            </:col>
            <:col :let={host} label={gettext("Actions")}>
              <div class="flex flex-wrap gap-2">
                <.dm_btn
                  :if={!host["enabled"]}
                  id={"codex-start-#{host["id"]}"}
                  size="sm"
                  variant="primary"
                  phx-click="start"
                  phx-value-id={host["id"]}
                >
                  {gettext("Start")}
                </.dm_btn>
                <.dm_btn
                  :if={host["enabled"]}
                  id={"codex-stop-#{host["id"]}"}
                  size="sm"
                  phx-click="stop"
                  phx-value-id={host["id"]}
                >
                  {gettext("Stop")}
                </.dm_btn>
                <.dm_btn
                  :if={host["enabled"]}
                  id={"codex-reconnect-#{host["id"]}"}
                  size="sm"
                  phx-click="reconnect"
                  phx-value-id={host["id"]}
                >
                  {gettext("Reconnect")}
                </.dm_btn>
              </div>
            </:col>
          </.dm_table>
        </div>
      </.dm_card>
      <.dm_card variant="bordered">
        <:title>{gettext("Add Codex")}</:title>
        <p class="mb-4 text-sm text-on-surface-variant">
          {gettext(
            "Creates a Codex Agent and its WebSocket connection, then starts connecting. For another machine, forward its app-server port first, for example `ssh -N -L 47812:127.0.0.1:47811 host`, and use ws://127.0.0.1:47812. SSH daemon connections are configured on the Agent page."
          )}
        </p>
        <p :if={@error} id="codex-error" role="alert" class="mb-4 text-error">{@error}</p>
        <.form for={@form} id="codex-add" phx-change="change" phx-submit="add" class="space-y-4">
          <input
            :for={key <- ~w(agent_command_id host_command_id enable_command_id)}
            type="hidden"
            name={"codex[#{key}]"}
            value={@form.params[key]}
          />
          <div class="grid gap-4 sm:grid-cols-2">
            <.dm_input
              field={@form[:name]}
              label={gettext("Name")}
              placeholder="Codex on mbp"
              required
            />
            <.dm_input
              field={@form[:url]}
              label={gettext("App-server URL (ws://127.0.0.1:PORT)")}
              required
            />
            <.dm_input
              field={@form[:version]}
              label={gettext("Expected Codex version (the connection reports the actual one)")}
              required
            />
            <.dm_input
              field={@form[:token_ref]}
              label={gettext("Token reference (optional, no secret)")}
              maxlength="200"
            />
          </div>
          <.dm_btn native_submit type="submit" variant="primary" phx-disable-with={gettext("Adding…")}>
            {gettext("Add and connect")}
          </.dm_btn>
        </.form>
      </.dm_card>
    </section>
    """
  end
end
