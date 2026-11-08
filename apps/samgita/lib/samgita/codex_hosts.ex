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
  alias Samgita.Domain.{Agent, CodexHost}

  @websocket_fields ~w(url connect_address token_ref allow_insecure)
  @secret_keys ~w(token password secret private_key key passphrase authorization)
  @reference ~r/\A[A-Za-z0-9][A-Za-z0-9._:\/-]{0,199}\z/
  @projection ~w(id agent_id transport url connect_address token_ref allow_insecure enabled generation server_version last_connected_at version inserted_at updated_at)a

  def list(principal) do
    with :ok <- operator(principal) do
      hosts = Repo.all(from h in CodexHost, order_by: [asc: h.inserted_at, asc: h.id])
      {:ok, Enum.map(hosts, &projection/1)}
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
  def record_connected(host_id, server_version) do
    system(host_id, fn ctx, host ->
      host =
        host
        |> change(
          generation: host.generation + 1,
          server_version: server_version,
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
    host
    |> cast(attrs, ~w(transport)a ++ Enum.map(@websocket_fields, &String.to_existing_atom/1))
    |> validate_required([:transport])
    |> validate_inclusion(:transport, ["websocket"])
    |> validate_websocket()
  end

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
