defmodule Samgita.Management do
  @moduledoc """
  Bounded, operator-only read models for the management UI.

  All writes still go through domain commands. Availability describes persisted
  evidence, never a live health check: connection registration is not a heartbeat.
  """
  import Ecto.Query
  alias Samgita.{Commands, Events, Params, Projection, Repo}

  alias Samgita.Domain.{
    Agent,
    AgentConnection,
    AgentCredential,
    ArtifactReference,
    DecisionRecord,
    DomainEvent,
    EventDelivery,
    EventSubscription,
    ExecutionSession,
    GitHubProjectMapping,
    GitHubRepository,
    PlatformAuthority,
    Project,
    ProjectAgent,
    ProjectRepository,
    Schedule,
    Task,
    TaskAttempt
  }

  def overview(principal) do
    operator_read(principal, nil, fn _ ->
      %{
        "authority" => Projection.authority(Repo.get!(PlatformAuthority, 1)),
        "counts" => %{
          "agents" => Repo.aggregate(Agent, :count),
          "projects" => Repo.aggregate(Project, :count),
          "tasks" => Repo.aggregate(Task, :count),
          "awaiting_review" => count(from(t in Task, where: t.state == "awaiting_review")),
          "uncertain_attempts" => count(from(a in TaskAttempt, where: not a.effects_resolved)),
          "exhausted_deliveries" =>
            count(from(d in EventDelivery, where: d.state == "dead_letter"))
        }
      }
    end)
  end

  def agents(principal, params \\ %{}) do
    operator_read(principal, nil, fn _ ->
      {limit, offset} = page(params)
      records = Repo.all(from(a in Agent, order_by: a.id, limit: ^limit, offset: ^offset))
      evidence = agent_evidence(Enum.map(records, & &1.id))

      %{
        "data" => Enum.map(records, &agent_projection(&1, evidence)),
        "total" => Repo.aggregate(Agent, :count),
        "limit" => limit,
        "offset" => offset
      }
    end)
  end

  def agent(principal, id, params \\ %{}) do
    operator_read(principal, nil, fn _ ->
      if !Params.uuid?(id), do: Commands.fail!(:not_found)
      record = Repo.get(Agent, id) || Commands.fail!(:not_found)
      {limit, offset} = page(params)
      connections = from(c in AgentConnection, where: c.agent_id == ^id)
      credentials = from(c in AgentCredential, where: c.agent_id == ^id)
      sessions = from(s in ExecutionSession, where: s.agent_id == ^id)
      memberships = from(m in ProjectAgent, where: m.agent_id == ^id)

      %{
        "agent" => agent_projection(record, agent_evidence([id])),
        "connections" =>
          rows(connections, limit, offset)
          |> Enum.map(fn c ->
            Projection.connection(c)
            |> Map.merge(Projection.fields(c, ~w(inserted_at updated_at)a))
          end),
        "credentials" => rows(credentials, limit, offset) |> Enum.map(&Projection.credential/1),
        "sessions" => rows(sessions, limit, offset) |> Enum.map(&Projection.session/1),
        "memberships" =>
          Repo.all(
            from(m in memberships,
              join: p in Project,
              on: p.id == m.project_id,
              order_by: m.id,
              limit: ^limit,
              offset: ^offset,
              select: {m, p.name}
            )
          )
          |> Enum.map(fn {m, name} -> Map.put(Projection.member(m), "project_name", name) end),
        "limit" => limit,
        "offset" => offset,
        "totals" => %{
          "connections" => count(connections),
          "credentials" => count(credentials),
          "sessions" => count(sessions),
          "memberships" => count(memberships)
        }
      }
    end)
  end

  def projects(principal, params \\ %{}) do
    operator_read(principal, nil, fn _ ->
      {limit, offset} = page(params)

      %{
        "data" => rows(Project, limit, offset) |> Enum.map(&Projection.project/1),
        "total" => Repo.aggregate(Project, :count),
        "limit" => limit,
        "offset" => offset
      }
    end)
  end

  def project(principal, id, params \\ %{}) do
    operator_read(principal, id, fn ctx ->
      {limit, offset} = page(params)

      queries = %{
        "repositories" => from(r in ProjectRepository, where: r.project_id == ^id),
        "memberships" => from(m in ProjectAgent, where: m.project_id == ^id),
        "tasks" => from(t in Task, where: t.project_id == ^id),
        "schedules" => from(s in Schedule, where: s.project_id == ^id),
        "events" => from(e in DomainEvent, where: e.project_id == ^id),
        "deliveries" => from(d in EventDelivery, where: d.project_id == ^id),
        "github_mappings" => from(m in GitHubProjectMapping, where: m.project_id == ^id)
      }

      routing =
        Repo.get_by(EventSubscription, project_id: id, purpose: "responsible", enabled: true)

      %{
        "project" => Projection.project(ctx.project),
        "repositories" =>
          Samgita.Repositories.list_locked(id, %{"limit" => limit, "offset" => offset}),
        "memberships" => members(queries["memberships"], limit, offset),
        "tasks" => rows(queries["tasks"], limit, offset) |> Enum.map(&Projection.task/1),
        "schedules" =>
          rows(queries["schedules"], limit, offset) |> Enum.map(&schedule_projection/1),
        "events" =>
          Repo.all(
            from(e in queries["events"],
              order_by: [desc: e.sequence],
              limit: ^limit,
              offset: ^offset
            )
          )
          |> Enum.map(&Events.event_projection/1),
        "deliveries" =>
          rows(queries["deliveries"], limit, offset) |> Enum.map(&Samgita.EventDelivery.project/1),
        "github_mappings" => github_mappings(queries["github_mappings"], limit, offset),
        "routing" => if(routing, do: Events.subscription_projection(routing)),
        "agent_choices" =>
          Repo.all(from(a in Agent, order_by: a.id, limit: 100))
          |> Enum.map(&Projection.fields(&1, ~w(id name enabled)a)),
        "agent_choices_total" => Repo.aggregate(Agent, :count),
        "limit" => limit,
        "offset" => offset,
        "totals" => Map.new(queries, fn {key, query} -> {key, count(query)} end)
      }
    end)
  end

  def task(principal, project_id, id, params \\ %{}) do
    operator_read(principal, project_id, fn ctx ->
      if !Params.uuid?(id), do: Commands.fail!(:not_found)
      task = Repo.get_by(Task, id: id, project_id: project_id) || Commands.fail!(:not_found)
      {limit, offset} = page(params)
      attempts = from(a in TaskAttempt, where: a.project_id == ^project_id and a.task_id == ^id)

      decisions =
        from(d in DecisionRecord, where: d.project_id == ^project_id and d.task_id == ^id)

      artifacts =
        from(a in ArtifactReference, where: a.project_id == ^project_id and a.task_id == ^id)

      children = from(t in Task, where: t.project_id == ^project_id and t.parent_task_id == ^id)

      progress =
        from(e in DomainEvent,
          where:
            e.project_id == ^project_id and e.type == "attempt.progress" and
              fragment("?->>'task_id'", e.data) == ^id
        )

      review =
        Repo.one(
          from(d in decisions,
            where: d.kind == "review",
            order_by: [desc: d.inserted_at, desc: d.id],
            limit: 1
          )
        )

      %{
        "task" => Projection.task(task),
        "project" => Projection.project(ctx.project),
        "current_review_approved" => approved_review?(review, task),
        "attempts" =>
          Repo.all(
            from(a in attempts,
              join: agent in Agent,
              on: agent.id == a.agent_id,
              order_by: [desc: a.number],
              limit: ^limit,
              offset: ^offset,
              select: {a, agent.name}
            )
          )
          |> Enum.map(fn {a, name} -> Map.put(Projection.attempt(a), "agent_name", name) end),
        "decisions" => rows(decisions, limit, offset) |> Enum.map(&Projection.decision/1),
        "artifacts" => rows(artifacts, limit, offset) |> Enum.map(&Projection.artifact/1),
        "children" => rows(children, limit, offset) |> Enum.map(&Projection.task/1),
        "progress" => rows(progress, limit, offset) |> Enum.map(&Events.event_projection/1),
        "limit" => limit,
        "offset" => offset,
        "totals" => %{
          "attempts" => count(attempts),
          "decisions" => count(decisions),
          "artifacts" => count(artifacts),
          "children" => count(children),
          "progress" => count(progress)
        }
      }
    end)
  end

  defp operator_read(principal, project_id, callback) do
    Commands.read(principal, project_id, [], fn ctx ->
      Commands.operator!(principal)
      callback.(ctx)
    end)
  end

  defp approved_review?(nil, _task), do: false

  defp approved_review?(review, task),
    do: review.verdict == "approve" && review.metadata["task_version"] == task.version - 1

  defp members(query, limit, offset) do
    Repo.all(
      from(m in query,
        join: a in Agent,
        on: a.id == m.agent_id,
        order_by: m.id,
        limit: ^limit,
        offset: ^offset,
        select: {m, a.name}
      )
    )
    |> Enum.map(fn {m, name} -> Map.put(Projection.member(m), "agent_name", name) end)
  end

  defp github_mappings(query, limit, offset) do
    Repo.all(
      from(m in query,
        join: r in GitHubRepository,
        on: r.id == m.github_repository_id,
        order_by: m.id,
        limit: ^limit,
        offset: ^offset,
        select: {m, r}
      )
    )
    |> Enum.map(fn {m, r} -> Samgita.GitHub.mapping_projection(m, r) end)
  end

  defp schedule_projection(s),
    do:
      Projection.fields(
        s,
        ~w(id project_id expression timezone event_type payload enabled revision version scanned_through inserted_at updated_at)a
      )

  defp agent_evidence(ids) do
    connections =
      Repo.all(
        from(c in AgentConnection,
          where: c.agent_id in ^ids,
          distinct: c.agent_id,
          order_by: [asc: c.agent_id, desc: c.generation]
        )
      )
      |> Map.new(&{&1.agent_id, &1})

    deliveries =
      Repo.all(
        from(d in EventDelivery,
          where: d.agent_id in ^ids,
          distinct: d.agent_id,
          order_by: [asc: d.agent_id, desc: d.updated_at, desc: d.id]
        )
      )
      |> Map.new(&{&1.agent_id, &1})

    actors = Enum.map(ids, &("agent:" <> &1))

    activity =
      Repo.all(
        from(e in DomainEvent,
          where: e.actor in ^actors and e.type != "agent.connected",
          group_by: e.actor,
          select: {e.actor, max(e.created_at)}
        )
      )
      |> Map.new(fn {"agent:" <> id, at} -> {id, at} end)

    %{connections: connections, deliveries: deliveries, activity: activity}
  end

  defp agent_projection(agent, evidence) do
    connection = evidence.connections[agent.id]
    delivery = evidence.deliveries[agent.id]
    activity = evidence.activity[agent.id]
    # Connection creation alone is deliberately excluded from activity evidence.
    acknowledged = delivery && (delivery.completed_at || delivery.accepted_at)
    last_activity = latest(activity, acknowledged)
    recent = last_activity && DateTime.diff(DateTime.utc_now(), last_activity) <= 300

    connection_state = connection_state(connection)

    Projection.agent(agent)
    |> Map.merge(%{
      "credential_ref" => agent.credential_ref,
      "availability" => availability(agent.enabled, recent, connection_state),
      "connection_state" => connection_state,
      "last_activity_at" => if(last_activity, do: DateTime.to_iso8601(last_activity)),
      "last_delivery_state" => delivery && delivery.state
    })
  end

  defp connection_state(nil), do: "none"

  defp connection_state(connection),
    do: if(Commands.expired?(connection.expires_at), do: "expired", else: connection.state)

  defp availability(false, _, _), do: "disabled"
  defp availability(_, true, _), do: "activity observed"
  defp availability(_, _, "connected"), do: "stale"
  defp availability(_, _, _), do: "offline"

  defp latest(nil, other), do: other
  defp latest(other, nil), do: other
  defp latest(a, b), do: if(DateTime.compare(a, b) == :gt, do: a, else: b)
  defp count(query), do: Repo.aggregate(query, :count)

  defp rows(query, limit, offset),
    do:
      Repo.all(
        from(r in query,
          order_by: [desc: r.inserted_at, desc: r.id],
          limit: ^limit,
          offset: ^offset
        )
      )

  defp page(params), do: params |> Params.strings() |> Map.put_new("limit", 25) |> Params.page()
end
