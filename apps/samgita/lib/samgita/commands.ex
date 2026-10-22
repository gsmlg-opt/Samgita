defmodule Samgita.Commands do
  @moduledoc "Transactional authorization, ordered locks and secret-free command receipts."
  import Ecto.Query
  alias Samgita.{Error, Params, Principal, Repo}

  alias Samgita.Domain.{
    Agent,
    AgentConnection,
    AgentCredential,
    CommandReceipt,
    DomainEvent,
    PlatformAuthority,
    Project,
    ProjectAgent
  }

  def run(principal, project_id, attrs, opts, callback) do
    attrs = Params.strings(attrs)
    operation = Keyword.fetch!(opts, :operation)

    transaction(fn ->
      if !Params.uuid?(attrs["command_id"]), do: fail!(:invalid, %{field: "command_id"})

      context =
        lock_context!(principal, project_id, opts) |> Map.put(:command_id, attrs["command_id"])

      if Keyword.get(opts, :execution, false), do: require_hub!(context)
      # Serialize duplicate commands even when they create a new aggregate.
      Ecto.Adapters.SQL.query!(Repo, "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
        actor_key(principal) <> attrs["command_id"]
      ])

      digest = digest({operation, project_id, semantic(attrs)})
      actor = actor_key(principal)

      case Repo.get_by(CommandReceipt, principal: actor, command_id: attrs["command_id"]) do
        nil ->
          result =
            case callback.(context) do
              {:ok, result} -> result
              {:error, %Error{} = error} -> Repo.rollback(error)
              {:error, %Ecto.Changeset{} = changeset} -> invalid!(changeset)
              result when is_map(result) -> result
            end

          event_ids =
            Repo.all(
              from e in DomainEvent,
                where: e.actor == ^actor and e.command_id == ^attrs["command_id"],
                order_by: [asc: e.inserted_at, asc: e.id],
                select: e.id
            )

          %CommandReceipt{}
          |> Ecto.Changeset.change(
            principal: actor,
            command_id: attrs["command_id"],
            operation: operation,
            request_digest: digest,
            result: result,
            event_ids: event_ids,
            execution_epoch: if(Keyword.get(opts, :execution, false), do: context.authority.epoch)
          )
          |> Repo.insert!()

          result

        receipt ->
          if receipt.request_digest != digest,
            do: fail!(:conflict, %{reason: "command_id_reused"})

          if receipt.execution_epoch && receipt.execution_epoch != context.authority.epoch,
            do: fail!(:ownership_lost)

          receipt.result
      end
    end)
  end

  def read(principal, project_id, roles, callback) do
    transaction(fn -> callback.(lock_context!(principal, project_id, roles: roles)) end)
  end

  def transaction(fun) do
    Repo.transaction(fun)
  rescue
    _ in Ecto.StaleEntryError -> {:error, Error.new(:stale_version)}
    _ in Ecto.ConstraintError -> {:error, Error.new(:conflict)}
    _ in Ecto.CastError -> {:error, Error.new(:invalid)}
  end

  defp lock_context!(%Principal{} = principal, project_id, opts) do
    authority_query = from a in PlatformAuthority, where: a.id == 1

    authority_query =
      if Keyword.get(opts, :authority_write, false),
        do: lock(authority_query, "FOR UPDATE"),
        else: lock(authority_query, "FOR SHARE")

    authority = Repo.one!(authority_query)

    ids =
      ([principal.agent_id] ++ Keyword.get(opts, :agent_ids, []))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    if Enum.any?(ids, &(!Params.uuid?(&1))), do: fail!(:invalid)
    agents = Repo.all(from a in Agent, where: a.id in ^ids, order_by: a.id, lock: "FOR UPDATE")

    project =
      if project_id do
        if !Params.uuid?(project_id), do: fail!(:not_found)

        Repo.one(from p in Project, where: p.id == ^project_id, lock: "FOR UPDATE") ||
          fail!(:not_found)
      end

    authenticate!(principal, agents)
    authorize!(principal, project_id, Keyword.get(opts, :roles, []))
    %{principal: principal, project: project, authority: authority}
  end

  defp lock_context!(_, _, _), do: fail!(:unauthorized)

  defp authenticate!(%Principal{kind: :operator}, _), do: :ok

  defp authenticate!(%Principal{kind: :agent} = principal, agents) do
    agent = Enum.find(agents, &(&1.id == principal.agent_id)) || fail!(:unauthorized)
    if !agent.enabled, do: fail!(:unauthorized)
    credential = Repo.get(AgentCredential, principal.credential_id) || fail!(:unauthorized)

    if credential.agent_id != agent.id || credential.revoked_at ||
         expired?(credential.expires_at),
       do: fail!(:unauthorized)

    if principal.connection_id do
      connection = Repo.get(AgentConnection, principal.connection_id) || fail!(:unauthorized)

      if connection.agent_id != agent.id || connection.credential_id != credential.id ||
           connection.state != "connected" || expired?(connection.expires_at) ||
           connection.generation != principal.generation ||
           agent.generation != principal.generation,
         do: fail!(:unauthorized)
    end

    :ok
  end

  defp authenticate!(_, _), do: fail!(:unauthorized)

  defp authorize!(%Principal{kind: :operator}, _, _), do: :ok

  defp authorize!(%Principal{kind: :agent} = principal, nil, roles) do
    if roles != [:credential], do: fail!(:forbidden)
    if principal.connection_id && roles == [:credential], do: :ok
  end

  defp authorize!(%Principal{kind: :agent} = principal, project_id, roles) do
    if !principal.connection_id, do: fail!(:unauthorized)
    member = Repo.get_by(ProjectAgent, project_id: project_id, agent_id: principal.agent_id)

    if !member || !member.enabled || !Enum.any?(member.roles, &(&1 in roles)),
      do: fail!(:forbidden)

    :ok
  end

  def operator!(%Principal{kind: :operator}), do: :ok
  def operator!(_), do: fail!(:forbidden)

  def connection!(%{principal: %Principal{kind: :agent, connection_id: id}}) when is_binary(id),
    do: :ok

  def connection!(_), do: fail!(:unauthorized)

  def expect!(%{version: version}, attrs) do
    if attrs["expected_version"] != version,
      do: fail!(:stale_version, %{current_version: version})

    :ok
  end

  def require_hub!(%{authority: a}) do
    if a.owner != "hub" || !a.admission_open, do: fail!(:execution_closed)
    :ok
  end

  def fail!(code, details \\ %{}), do: Repo.rollback(Error.new(code, details))

  def insert!(changeset) do
    case Repo.insert(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> invalid!(changeset)
    end
  end

  def update!(changeset) do
    case Repo.update(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> invalid!(changeset)
    end
  end

  def invalid!(changeset) do
    fields = changeset.errors |> Keyword.keys() |> Enum.map(&to_string/1) |> Enum.uniq()
    fail!(:invalid, %{fields: fields})
  end

  def digest(value),
    do:
      :crypto.hash(:sha256, :erlang.term_to_binary(canonical(value)))
      |> Base.encode16(case: :lower)

  defp semantic(attrs) do
    safe = Map.drop(attrs, ~w(command_id proof correlation_id transport_request_id credential))

    if Map.has_key?(attrs, "credential"),
      do: Map.put(safe, "credential_fingerprint", digest(attrs["credential"])),
      else: safe
  end

  defp canonical(map) when is_map(map),
    do: map |> Enum.map(fn {k, v} -> {k, canonical(v)} end) |> Enum.sort()

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> canonical()
  defp canonical(other), do: other
  def actor_key(%Principal{kind: :operator}), do: "operator"
  def actor_key(%Principal{kind: :agent, agent_id: id}), do: "agent:" <> id
  def expired?(nil), do: false
  def expired?(time), do: DateTime.compare(time, DateTime.utc_now()) != :gt
end
