defmodule Samgita.Commands do
  @moduledoc "Transactional authorization, ordered locks and secret-free command receipts."
  import Ecto.Query
  alias Ecto.Adapters.SQL
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

    transaction(fn ->
      if !Params.uuid?(attrs["command_id"]), do: fail!(:invalid, %{field: "command_id"})

      context =
        lock_context!(principal, project_id, opts) |> Map.put(:command_id, attrs["command_id"])

      if Keyword.get(opts, :execution, false), do: require_hub!(context)
      # Serialize duplicate commands even when they create a new aggregate.
      SQL.query!(Repo, "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
        actor_key(principal) <> attrs["command_id"]
      ])

      execute_or_replay!(context, project_id, attrs, opts, callback)
    end)
  end

  defp execute_or_replay!(context, project_id, attrs, opts, callback) do
    actor = actor_key(context.principal)
    operation = Keyword.fetch!(opts, :operation)
    legacy_digest = digest({operation, project_id, semantic(attrs)})
    target = Keyword.get(opts, :target)

    request_digest =
      if Keyword.has_key?(opts, :target),
        do: digest({operation, project_id, target, semantic(attrs)}),
        else: legacy_digest

    receipt = Repo.get_by(CommandReceipt, principal: actor, command_id: attrs["command_id"])

    case {receipt, Keyword.get(opts, :replay_only, false)} do
      {nil, true} ->
        :missing

      {nil, false} ->
        result = command_result!(callback.(context))
        store_receipt!(context, attrs, opts, request_digest, result)
        result

      {receipt, _} ->
        validate_replay!(
          receipt,
          context,
          request_digest,
          {operation, project_id, target, legacy_digest}
        )

        receipt.result
    end
  end

  defp command_result!({:ok, result}), do: result
  defp command_result!({:error, %Error{} = error}), do: Repo.rollback(error)
  defp command_result!({:error, %Ecto.Changeset{} = changeset}), do: invalid!(changeset)
  defp command_result!(result) when is_map(result), do: result

  defp store_receipt!(context, attrs, opts, request_digest, result) do
    actor = actor_key(context.principal)

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
      operation: Keyword.fetch!(opts, :operation),
      request_digest: request_digest,
      result: result,
      event_ids: event_ids,
      execution_epoch: if(Keyword.get(opts, :execution, false), do: context.authority.epoch)
    )
    |> Repo.insert!()
  end

  defp validate_replay!(receipt, context, request_digest, legacy) do
    if receipt.request_digest != request_digest && !legacy_target_match?(receipt, legacy),
      do: fail!(:conflict, %{reason: "command_id_reused"})

    if receipt.execution_epoch && receipt.execution_epoch != context.authority.epoch,
      do: fail!(:ownership_lost)
  end

  # Pre-target receipts are immutable. Replay requires stored proof of the same
  # target and scope; an ambiguous old command is never executed again.
  defp legacy_target_match?(receipt, {operation, project_id, target, legacy_digest}) do
    target && receipt.operation == operation && receipt.request_digest == legacy_digest &&
      receipt.result["id"] == target && receipt.result["project_id"] == project_id
  end

  @doc "Check an authenticated command receipt before external preparation; never creates a receipt."
  def replay(principal, project_id, attrs, opts) do
    run(principal, project_id, attrs, Keyword.put(opts, :replay_only, true), fn _ ->
      raise "replay cannot execute a command"
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

  @doc false
  def system(project_id, agent_ids, callback) do
    transaction(fn ->
      callback.(lock_context!(Principal.operator(), project_id, agent_ids: agent_ids))
    end)
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
    # Agent identities are immutable. This still serializes capacity/credential
    # updates, while allowing an outbox FK's KEY SHARE after its Project lock.
    agents =
      Repo.all(from a in Agent, where: a.id in ^ids, order_by: a.id, lock: "FOR NO KEY UPDATE")

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

    authenticate_connection!(principal, agent, credential)

    :ok
  end

  defp authenticate!(_, _), do: fail!(:unauthorized)

  defp authenticate_connection!(%{connection_id: nil}, _, _), do: :ok

  defp authenticate_connection!(principal, agent, credential) do
    connection = Repo.get(AgentConnection, principal.connection_id) || fail!(:unauthorized)

    if connection.agent_id != agent.id || connection.credential_id != credential.id ||
         connection.state != "connected" || expired?(connection.expires_at) ||
         connection.generation != principal.generation ||
         agent.generation != principal.generation,
       do: fail!(:unauthorized)
  end

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
