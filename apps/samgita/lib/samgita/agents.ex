defmodule Samgita.Agents do
  @moduledoc "Stable machine registrations, credential references, connection instances and external sessions."
  import Ecto.Query
  import Ecto.Changeset
  alias Samgita.{Commands, Error, Events, Params, Principal, Projection, Repo}
  alias Samgita.Domain.{Agent, AgentConnection, AgentCredential, ExecutionSession}
  @read_roles ~w(observer worker manager reviewer)
  @fields ~w(name implementation enabled capacity advertised_capabilities approved_capabilities protocol protocol_version endpoint_metadata credential_ref)a

  def register(principal, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(principal, nil, attrs, [operation: "agent.register"], fn ctx ->
      Commands.operator!(principal)
      agent = Commands.insert!(agent_changeset(%Agent{}, attrs))
      Events.append!(nil, "agent.registered", ctx, "agent", agent.id, %{}, current: agent)
      Projection.agent(agent)
    end)
  end

  def update(principal, id, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      nil,
      attrs,
      [operation: "agent.update:" <> to_string(id), agent_ids: [id]],
      fn ctx ->
        Commands.operator!(principal)
        agent = Repo.get(Agent, id) || Commands.fail!(:not_found)
        Commands.expect!(agent, attrs)
        previous = agent

        agent =
          agent
          |> agent_changeset(attrs)
          |> put_change(:version, agent.version + 1)
          |> Commands.update!()

        Events.append!(nil, "agent.updated", ctx, "agent", id, %{},
          previous: previous,
          current: agent
        )

        Projection.agent(agent)
      end
    )
  end

  def get(principal, id) do
    Commands.read(principal, nil, [], fn _ ->
      Commands.operator!(principal)
      if !Params.uuid?(id), do: Commands.fail!(:not_found)
      Projection.agent(Repo.get(Agent, id) || Commands.fail!(:not_found))
    end)
  end

  def list(principal, params \\ %{}) do
    Commands.read(principal, nil, [], fn _ ->
      Commands.operator!(principal)
      {limit, offset} = Params.page(params)
      data = Repo.all(from a in Agent, order_by: a.id, limit: ^limit, offset: ^offset)
      %{"data" => Enum.map(data, &Projection.agent/1), "limit" => limit, "offset" => offset}
    end)
  end

  def put_credential(principal, id, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      nil,
      attrs,
      [operation: "credential.put:" <> to_string(id), agent_ids: [id]],
      fn ctx ->
        Commands.operator!(principal)
        agent = Repo.get(Agent, id) || Commands.fail!(:not_found)
        Commands.expect!(agent, attrs)
        credential = attrs["credential"]

        if !is_binary(credential) || byte_size(credential) < 32 || byte_size(credential) > 4096,
          do: Commands.fail!(:invalid, %{field: "credential"})

        changeset =
          %AgentCredential{}
          |> cast(attrs, [:reference, :expires_at])
          |> validate_length(:reference, max: 512)
          |> put_change(:agent_id, id)
          |> put_change(:digest, :crypto.hash(:sha256, credential))
          |> unique_constraint(:digest)

        record = Commands.insert!(changeset)
        current = agent |> change(version: agent.version + 1) |> Commands.update!()

        Events.append!(
          nil,
          "agent.credential_added",
          ctx,
          "agent",
          id,
          %{
            "credential_id" => record.id
          },
          previous: agent,
          current: current
        )

        Projection.credential(record)
      end
    )
  end

  def revoke_credential(principal, id, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      nil,
      attrs,
      [operation: "credential.revoke:" <> to_string(id), agent_ids: [id]],
      fn ctx ->
        Commands.operator!(principal)
        agent = Repo.get(Agent, id) || Commands.fail!(:not_found)
        Commands.expect!(agent, attrs)
        if !Params.uuid?(attrs["credential_id"]), do: Commands.fail!(:not_found)
        record = Repo.get(AgentCredential, attrs["credential_id"]) || Commands.fail!(:not_found)
        if record.agent_id != id, do: Commands.fail!(:not_found)
        record = record |> change(revoked_at: DateTime.utc_now()) |> Commands.update!()

        Repo.update_all(
          from(c in AgentConnection,
            where: c.credential_id == ^record.id and c.state == "connected"
          ),
          set: [state: "revoked"]
        )

        current = agent |> change(version: agent.version + 1) |> Commands.update!()

        Events.append!(
          nil,
          "agent.credential_revoked",
          ctx,
          "agent",
          id,
          %{
            "credential_id" => record.id
          },
          previous: agent,
          current: current
        )

        Projection.credential(record)
      end
    )
  end

  def authenticate(raw) when is_binary(raw) and byte_size(raw) >= 32 and byte_size(raw) <= 4096 do
    digest = :crypto.hash(:sha256, raw)

    case Repo.get_by(AgentCredential, digest: digest) do
      %AgentCredential{revoked_at: nil} = c ->
        a = Repo.get(Agent, c.agent_id)

        if a && a.enabled && !Commands.expired?(c.expires_at),
          do: {:ok, %Principal{kind: :agent, agent_id: a.id, credential_id: c.id}},
          else: {:error, Error.new(:unauthorized)}

      _ ->
        {:error, Error.new(:unauthorized)}
    end
  end

  def authenticate(_), do: {:error, Error.new(:unauthorized)}

  def bind_connection(%Principal{kind: :agent} = principal, id) do
    Commands.read(principal, nil, [:credential], fn _ ->
      if !Params.uuid?(id), do: Commands.fail!(:unauthorized)
      c = Repo.get(AgentConnection, id) || Commands.fail!(:unauthorized)
      a = Repo.get!(Agent, principal.agent_id)

      if c.agent_id != principal.agent_id || c.credential_id != principal.credential_id ||
           c.state != "connected" || c.generation != a.generation ||
           Commands.expired?(c.expires_at),
         do: Commands.fail!(:unauthorized)

      %{principal | connection_id: c.id, generation: c.generation}
    end)
  end

  def bind_connection(_, _), do: {:error, Error.new(:unauthorized)}

  def connect(principal, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      nil,
      attrs,
      [operation: "agent.connect", roles: [:credential]],
      fn ctx ->
        if principal.kind != :agent, do: Commands.fail!(:forbidden)
        agent = Repo.get!(Agent, principal.agent_id)
        previous = agent

        Repo.update_all(
          from(c in AgentConnection, where: c.agent_id == ^agent.id and c.state == "connected"),
          set: [state: "replaced"]
        )

        agent =
          agent
          |> change(generation: agent.generation + 1, version: agent.version + 1)
          |> Commands.update!()

        connection =
          %AgentConnection{}
          |> change(
            agent_id: agent.id,
            credential_id: principal.credential_id,
            generation: agent.generation,
            state: "connected",
            expires_at: DateTime.add(DateTime.utc_now(), 86_400, :second)
          )
          |> Repo.insert!()

        Events.append!(
          nil,
          "agent.connected",
          ctx,
          "agent",
          agent.id,
          %{
            "connection_id" => connection.id,
            "generation" => connection.generation
          },
          previous: previous,
          current: agent
        )

        Projection.connection(connection)
      end
    )
  end

  def open_session(principal, project_id, attrs) do
    attrs = Params.strings(attrs)
    agent_id = if principal.kind == :agent, do: principal.agent_id, else: attrs["agent_id"]

    Commands.run(
      principal,
      project_id,
      attrs,
      [operation: "session.open", roles: ~w(worker manager), agent_ids: [agent_id]],
      fn ctx ->
        connection_id =
          if principal.kind == :agent, do: principal.connection_id, else: attrs["connection_id"]

        if !Params.uuid?(connection_id) || !Params.uuid?(agent_id), do: Commands.fail!(:invalid)
        c = Repo.get(AgentConnection, connection_id) || Commands.fail!(:not_found)
        a = Repo.get!(Agent, agent_id)

        if !current_connection?(c, a),
          do: Commands.fail!(:unauthorized)

        session =
          %ExecutionSession{}
          |> cast(attrs, [:external_id])
          |> validate_required([:external_id])
          |> validate_length(:external_id, max: 256)
          |> change(project_id: project_id, agent_id: agent_id, connection_id: connection_id)
          |> unique_constraint([:agent_id, :project_id, :external_id])
          |> Commands.insert!()

        Events.append!(project_id, "session.recorded", ctx, "execution_session", session.id, %{},
          current: session
        )

        Projection.session(session)
      end
    )
  end

  defp current_connection?(connection, agent) do
    connection.agent_id == agent.id && connection.state == "connected" &&
      connection.generation == agent.generation && !Commands.expired?(connection.expires_at)
  end

  def list_sessions(principal, project_id, params \\ %{}) do
    Commands.read(principal, project_id, @read_roles, fn _ ->
      {limit, offset} = Params.page(params)

      data =
        Repo.all(
          from s in ExecutionSession,
            where: s.project_id == ^project_id,
            order_by: s.id,
            limit: ^limit,
            offset: ^offset
        )

      %{"data" => Enum.map(data, &Projection.session/1), "limit" => limit, "offset" => offset}
    end)
  end

  defp agent_changeset(agent, attrs) do
    changeset =
      agent
      |> cast(attrs, @fields)
      |> validate_required([:name, :protocol, :protocol_version])
      |> validate_length(:name, min: 1, max: 200)
      |> validate_length(:implementation, max: 200)
      |> validate_length(:credential_ref, max: 512)
      |> validate_number(:capacity, greater_than: 0, less_than_or_equal_to: 1000)
      |> validate_inclusion(:protocol, ["samgita"])
      |> validate_inclusion(:protocol_version, [SamgitaProtocol.version()])

    advertised = get_field(changeset, :advertised_capabilities)
    approved = get_field(changeset, :approved_capabilities)

    changeset =
      if SamgitaProtocol.Capabilities.validate(advertised) != :ok ||
           !is_list(approved) || !Enum.all?(approved, &(&1 in (advertised || []))),
         do: add_error(changeset, :advertised_capabilities, "invalid capabilities"),
         else: changeset

    endpoint = get_field(changeset, :endpoint_metadata)

    if valid_endpoint?(endpoint),
      do: changeset,
      else: add_error(changeset, :endpoint_metadata, "invalid endpoint")
  end

  defp valid_endpoint?(metadata) when is_map(metadata) do
    Enum.all?(Map.keys(metadata), &(&1 in ~w(url transport))) &&
      metadata["transport"] in [nil, "websocket", "stdio"] &&
      valid_endpoint_url?(metadata["url"])
  end

  defp valid_endpoint?(_), do: false
  defp valid_endpoint_url?(nil), do: true

  defp valid_endpoint_url?(value) when is_binary(value) do
    uri = URI.parse(value)

    uri.scheme in ~w(https wss http ws) && is_binary(uri.host) && uri.userinfo == nil &&
      uri.query == nil && uri.fragment == nil
  end

  defp valid_endpoint_url?(_), do: false
end
