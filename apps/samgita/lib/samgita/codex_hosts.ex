defmodule Samgita.CodexHosts do
  @moduledoc """
  Operator-configured Codex app-server hosts (design §11).

  Configuration is durable and versioned; only credential reference names are
  stored. Live connection state belongs to `Samgita.CodexHosts.Runtime` and is
  evidence of reachability, never of Task progress or completion.
  """
  import Ecto.Query
  import Ecto.Changeset
  alias Samgita.{Commands, Error, Events, Params, Principal, Projection, Repo}
  alias Samgita.CodexHosts.Runtime
  alias SamgitaCodexDriver.Session
  alias Samgita.Domain.{Agent, CodexHost}

  @websocket_fields ~w(url connect_address token_ref allow_insecure)a
  @ssh_fields ~w(ssh_user ssh_host ssh_port ssh_key_ref known_hosts remote_codex_path remote_socket_path ensure_daemon)a
  @ssh_host ~r/\A[A-Za-z0-9][A-Za-z0-9.:-]{0,252}\z/
  @ssh_user ~r/\A[A-Za-z_][A-Za-z0-9_.-]{0,31}\z/
  @remote_path ~r/\A[A-Za-z0-9_.\/~+-]{1,512}\z/
  @secret_keys ~w(token password secret private_key key passphrase authorization)
  @reference ~r/\A[A-Za-z0-9][A-Za-z0-9._:\/-]{0,199}\z/
  @projection ~w(id agent_id installation_id machine_name transport url connect_address token_ref allow_insecure ssh_user ssh_host ssh_port ssh_key_ref known_hosts remote_codex_path remote_socket_path ensure_daemon enabled generation server_version last_connected_at version inserted_at updated_at)a

  def list(principal) do
    with :ok <- operator(principal) do
      rows =
        Repo.all(
          from h in CodexHost,
            join: a in Agent,
            on: a.id == h.agent_id,
            order_by: [asc: h.inserted_at, asc: h.id],
            select: {h, a.name}
        )

      names = Map.new(rows, fn {host, name} -> {host.id, name} end)

      {:ok,
       Enum.map(rows, fn {host, name} ->
         same = for {other, _} <- rows, same_machine?(host, other), do: names[other.id]

         host
         |> projection()
         |> Map.put("agent_name", name)
         |> Map.put("same_machine_as", same)
       end)}
    end
  end

  def get(principal, id) do
    with :ok <- operator(principal),
         %CodexHost{} = host <- fetch(id) do
      {:ok, projection(host)}
    else
      nil -> {:error, Error.new(:not_found)}
      error -> error
    end
  end

  def for_agent(principal, agent_id) do
    with :ok <- operator(principal) do
      host = Params.uuid?(agent_id) && Repo.get_by(CodexHost, agent_id: agent_id)
      {:ok, host && projection(host)}
    end
  end

  @doc "Create or update the host configuration of one Codex Agent. New hosts start disabled."
  def configure(principal, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      nil,
      attrs,
      [operation: "codex_host.configure", agent_ids: [attrs["agent_id"]]],
      fn ctx ->
        Commands.operator!(principal)
        if Enum.any?(@secret_keys, &Map.has_key?(attrs, &1)), do: Commands.fail!(:invalid)
        if !Params.uuid?(attrs["agent_id"]), do: Commands.fail!(:invalid, %{field: "agent_id"})

        agent = Repo.get(Agent, attrs["agent_id"]) || Commands.fail!(:not_found)
        if agent.runtime_driver != "codex", do: Commands.fail!(:invalid, %{field: "agent_id"})

        existing =
          Repo.one(from h in CodexHost, where: h.agent_id == ^agent.id, lock: "FOR UPDATE")

        {host, previous} =
          case existing do
            nil ->
              {%CodexHost{agent_id: agent.id} |> settings(attrs) |> Commands.insert!(), nil}

            host ->
              Commands.expect!(host, attrs)

              {host |> settings(attrs) |> change(version: host.version + 1) |> Commands.update!(),
               host}
          end

        audit!(ctx, host, "codex_host.configured", previous)
        projection(host)
      end
    )
    |> after_commit()
  end

  @doc """
  The projects Codex reports on this host (its `project/list`). Codex owns them;
  Samgita keeps no copy. Requires a connected host.
  """
  def projects(principal, id) do
    with :ok <- operator(principal),
         {:ok, session} <- live_session(id) do
      list_projects(session, nil, [])
    end
  end

  @doc """
  Add a project to Codex on this host (`project/create`). The command ID is the
  idempotency key, so a retry cannot create a second project.
  """
  def create_project(principal, id, attrs) do
    attrs = Params.strings(attrs)
    name = String.trim(attrs["name"] || "")
    path = String.trim(attrs["path"] || "")

    with :ok <- operator(principal),
         :ok <- validate_project(attrs["command_id"], name, path),
         {:ok, session} <- live_session(id),
         {:ok, %{"result" => %{"project" => created}}} <-
           codex_request(session, "project/create", %{
             "idempotencyKey" => attrs["command_id"],
             "name" => name,
             "roots" => [%{"path" => path}]
           }) do
      project = project(created)

      system(id, fn ctx, host ->
        Events.append!(nil, "codex_host.project_created", ctx, "codex_host", host.id, %{
          "agent_id" => host.agent_id,
          "project_id" => project["id"],
          "name" => project["name"]
        })
      end)

      {:ok, project}
    else
      {:ok, _} -> {:error, Error.new(:codex_request_failed)}
      error -> error
    end
  end

  @doc """
  List the folders in one directory on the Codex machine (`fs/readDirectory`),
  for choosing a project folder. Visible folders first, then hidden ones.
  """
  def read_directory(principal, id, path) do
    path = String.trim(path || "")

    with :ok <- operator(principal),
         :ok <- absolute_path(path),
         {:ok, session} <- live_session(id),
         {:ok, %{"result" => %{"entries" => entries}}} when is_list(entries) <-
           codex_request(session, "fs/readDirectory", %{"path" => path}) do
      folders =
        for %{"fileName" => name, "isDirectory" => true} <- entries, is_binary(name), do: name

      {hidden, visible} = Enum.split_with(folders, &String.starts_with?(&1, "."))
      {:ok, Enum.sort_by(visible, &String.downcase/1) ++ Enum.sort_by(hidden, &String.downcase/1)}
    else
      {:ok, _} -> {:error, Error.new(:codex_request_failed)}
      error -> error
    end
  end

  @doc "The user's home folder on a connected Codex machine, when Codex reported it."
  def home(id), do: Runtime.status(id)["home"]

  defp absolute_path(path) do
    if Path.type(path) == :absolute and byte_size(path) <= 4096 and
         not String.contains?(path, <<0>>),
       do: :ok,
       else: {:error, Error.new(:invalid, %{fields: [:path]})}
  end

  @project_pages 10

  defp list_projects(session, cursor, acc) do
    params = if cursor, do: %{"limit" => 100, "cursor" => cursor}, else: %{"limit" => 100}

    case codex_request(session, "project/list", params) do
      {:ok, %{"result" => %{"data" => data} = result}} when is_list(data) ->
        acc = acc ++ Enum.map(data, &project/1)
        next = result["nextCursor"]

        if is_binary(next) and length(acc) < 100 * @project_pages,
          do: list_projects(session, next, acc),
          else: {:ok, acc}

      {:ok, _} ->
        {:error, Error.new(:codex_request_failed)}

      error ->
        error
    end
  end

  defp project(p) when is_map(p),
    do: %{
      "id" => p["id"],
      "name" => p["name"],
      "roots" => for(%{"path" => path} <- List.wrap(p["roots"]), is_binary(path), do: path),
      "updated_at" => p["updatedAt"]
    }

  defp validate_project(command_id, name, path) do
    cond do
      !Params.uuid?(command_id) ->
        {:error, Error.new(:invalid, %{fields: [:command_id]})}

      name == "" or byte_size(name) > 200 ->
        {:error, Error.new(:invalid, %{fields: [:name]})}

      Path.type(path) != :absolute or byte_size(path) > 4096 or String.contains?(path, <<0>>) ->
        {:error, Error.new(:invalid, %{fields: [:path]})}

      true ->
        :ok
    end
  end

  defp live_session(id) do
    case fetch(id) && Runtime.session(id) do
      nil -> {:error, Error.new(:codex_unavailable)}
      false -> {:error, Error.new(:not_found)}
      session -> {:ok, session}
    end
  end

  defp codex_request(session, method, params) do
    case Session.request(session, method, params, timeout_ms: 15_000) do
      {:ok, %{"result" => _} = wire} -> {:ok, wire}
      _ -> {:error, Error.new(:codex_request_failed)}
    end
  catch
    :exit, _ -> {:error, Error.new(:codex_unavailable)}
  end

  @doc """
  Before adding a WebSocket host, connect to it once and report the Codex
  machine that answers, plus already configured Agents on the same machine
  (same Codex installation) or the same address. One machine should be one
  Agent; callers warn rather than create a duplicate silently.
  """
  def check_new(principal, attrs) do
    attrs = Params.strings(attrs)

    with :ok <- operator(principal),
         :ok <- validate_settings(attrs) do
      host = %CodexHost{} |> settings(attrs) |> apply_changes()

      identity =
        case probe(host) do
          {:ok, identity} -> identity
          _ -> %{installation_id: nil, machine_name: nil}
        end

      same =
        case identity.installation_id do
          nil -> dynamic([h], h.url == ^host.url)
          id -> dynamic([h], h.url == ^host.url or h.installation_id == ^id)
        end

      existing =
        Repo.all(
          from h in CodexHost,
            join: a in Agent,
            on: a.id == h.agent_id,
            where: ^same,
            select: a.name
        )

      {:ok,
       %{
         "reachable" => identity.installation_id != nil,
         "machine_name" => identity.machine_name,
         "same_machine_as" => existing
       }}
    end
  end

  @probe_timeout 8_000

  defp probe(host) do
    task =
      Task.Supervisor.async_nolink(Samgita.CodexHosts.ProbeSupervisor, fn ->
        Samgita.CodexHosts.Connection.identify(host)
      end)

    case Task.yield(task, @probe_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, identity}} -> {:ok, identity}
      _ -> {:error, :unreachable}
    end
  end

  defp same_machine?(host, other),
    do:
      other.id != host.id &&
        ((host.installation_id != nil && other.installation_id == host.installation_id) ||
           (host.url != nil && other.url == host.url))

  @doc "Validate host settings without writing, so a caller can check them before creating an Agent."
  def validate_settings(attrs) do
    changeset = settings(%CodexHost{}, Params.strings(attrs))

    if changeset.valid?,
      do: :ok,
      else: {:error, Error.new(:invalid, %{fields: Keyword.keys(changeset.errors)})}
  end

  def enable(principal, id, attrs), do: set_enabled(principal, id, attrs, true)
  def disable(principal, id, attrs), do: set_enabled(principal, id, attrs, false)

  @doc "Ask a running connection to reconnect now. Runtime only; changes no durable state."
  def reconnect(principal, id) do
    with :ok <- operator(principal),
         %CodexHost{} = host <- fetch(id) do
      Runtime.reconnect(host.id)
    else
      nil -> {:error, Error.new(:not_found)}
      error -> error
    end
  end

  def status(id), do: Runtime.status(id)

  @doc false
  def enabled_ids,
    do: Repo.all(from h in CodexHost, where: h.enabled, order_by: h.id, select: h.id)

  @doc false
  def load(id), do: fetch(id)

  @doc false
  def record_connected(host_id, server_version, identity \\ %{}) do
    system(host_id, fn ctx, host ->
      host =
        host
        |> change(
          generation: host.generation + 1,
          server_version: server_version,
          installation_id: identity[:installation_id] || host.installation_id,
          machine_name: identity[:machine_name] || host.machine_name,
          last_connected_at: DateTime.utc_now()
        )
        |> Repo.update!()

      Events.append!(nil, "codex_host.connected", ctx, "codex_host", host.id, %{
        "agent_id" => host.agent_id,
        "generation" => host.generation,
        "server_version" => host.server_version
      })

      host
    end)
  end

  @doc false
  def record_disconnected(host_id, generation, reason) when is_atom(reason) do
    system(host_id, fn ctx, host ->
      Events.append!(nil, "codex_host.disconnected", ctx, "codex_host", host.id, %{
        "agent_id" => host.agent_id,
        "generation" => generation,
        "reason" => to_string(reason)
      })

      host
    end)
  end

  defp set_enabled(principal, id, attrs, enabled) do
    attrs = Params.strings(attrs)

    agent_id =
      Params.uuid?(id) && Repo.one(from h in CodexHost, where: h.id == ^id, select: h.agent_id)

    operation =
      if(enabled, do: "codex_host.enable:", else: "codex_host.disable:") <> to_string(id)

    Commands.run(
      principal,
      nil,
      attrs,
      [operation: operation, agent_ids: List.wrap(agent_id || [])],
      fn ctx ->
        Commands.operator!(principal)
        host = (agent_id && lock!(id)) || Commands.fail!(:not_found)
        Commands.expect!(host, attrs)

        if host.enabled == enabled do
          projection(host)
        else
          previous = host
          host = host |> change(enabled: enabled, version: host.version + 1) |> Commands.update!()
          type = if enabled, do: "codex_host.enabled", else: "codex_host.disabled"
          audit!(ctx, host, type, previous)
          projection(host)
        end
      end
    )
    |> after_commit()
  end

  # Supervisor changes happen only after the configuration commits.
  defp after_commit({:ok, %{"id" => id}} = result) do
    Runtime.sync(id)
    result
  end

  defp after_commit(result), do: result

  defp settings(host, attrs) do
    changeset =
      host
      |> cast(attrs, [:transport | @websocket_fields ++ @ssh_fields])
      |> validate_required([:transport])
      |> validate_inclusion(:transport, ["websocket", "ssh"])

    # A host uses exactly one transport; the other transport's settings are cleared.
    case get_field(changeset, :transport) do
      "websocket" -> changeset |> clear(@ssh_fields) |> validate_websocket()
      "ssh" -> changeset |> clear(@websocket_fields) |> validate_ssh()
      _ -> changeset
    end
  end

  defp clear(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, acc ->
      default = if field in [:allow_insecure, :ensure_daemon], do: false
      put_change(acc, field, default)
    end)
  end

  defp validate_ssh(changeset) do
    changeset
    |> validate_required([:ssh_host, :known_hosts])
    |> validate_format(:ssh_host, @ssh_host)
    |> validate_format(:ssh_user, @ssh_user)
    |> validate_number(:ssh_port, greater_than: 0, less_than: 65_536)
    |> validate_format(:ssh_key_ref, @reference)
    |> validate_format(:remote_codex_path, @remote_path)
    |> validate_format(:remote_socket_path, @remote_path)
    |> validate_change(:known_hosts, fn :known_hosts, value ->
      if valid_known_hosts?(value), do: [], else: [known_hosts: "invalid"]
    end)
  end

  # OpenSSH known_hosts lines: "<hosts> <key-type> <base64>" with no options or
  # control characters. Private keys are rejected by this shape check.
  defp valid_known_hosts?(value) when byte_size(value) in 1..16_384 do
    lines = value |> String.split("\n", trim: true) |> Enum.map(&String.trim/1)

    lines != [] and
      Enum.all?(lines, fn line ->
        line =~
          ~r/\A[^\s@#][^\s]* (ssh-[a-z0-9-]+|ecdsa-sha2-[a-z0-9-]+|sk-[a-z0-9@.-]+) [A-Za-z0-9+\/]+={0,2}( [^\x00-\x1f]*)?\z/
      end)
  end

  defp valid_known_hosts?(_), do: false

  defp validate_websocket(changeset) do
    changeset
    |> validate_required([:url])
    |> validate_change(:url, fn :url, url ->
      if valid_url?(url), do: [], else: [url: "invalid"]
    end)
    |> validate_change(:connect_address, fn :connect_address, address ->
      if match?({:ok, _}, :inet.parse_strict_address(String.to_charlist(address))),
        do: [],
        else: [connect_address: "invalid"]
    end)
    |> validate_format(:token_ref, @reference)
  end

  defp valid_url?(url) when byte_size(url) <= 2048 do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host, userinfo: nil, fragment: nil}}
      when scheme in ["ws", "wss"] and is_binary(host) and host != "" ->
        true

      _ ->
        false
    end
  end

  defp valid_url?(_), do: false

  defp audit!(ctx, host, type, previous) do
    Events.append!(
      nil,
      type,
      ctx,
      "codex_host",
      host.id,
      %{"agent_id" => host.agent_id, "transport" => host.transport},
      previous: previous,
      current: host
    )
  end

  defp system(host_id, callback) do
    agent_id = Repo.one(from h in CodexHost, where: h.id == ^host_id, select: h.agent_id)

    if agent_id do
      Commands.system(nil, [agent_id], fn ctx ->
        ctx =
          Map.merge(ctx, %{
            command_id: Ecto.UUID.generate(),
            source: "codex_host",
            source_actor: "codex_host:" <> host_id
          })

        callback.(ctx, lock!(host_id))
      end)
    else
      {:error, Error.new(:not_found)}
    end
  end

  defp lock!(id), do: Repo.one!(from h in CodexHost, where: h.id == ^id, lock: "FOR UPDATE")

  defp fetch(id), do: if(Params.uuid?(id), do: Repo.get(CodexHost, id))

  defp operator(%Principal{kind: :operator}), do: :ok
  defp operator(_), do: {:error, Error.new(:forbidden)}

  defp projection(host),
    do: host |> Projection.fields(@projection) |> Map.put("status", Runtime.status(host.id))
end
