defmodule Samgita.Projects do
  @moduledoc "Project management and explicit membership grants; no execution lifecycle."
  import Ecto.Query
  import Ecto.Changeset
  alias Samgita.{Commands, Events, Params, Projection, Repo}
  alias Samgita.Domain.{Project, ProjectAgent}
  @read_roles ~w(observer worker manager reviewer)

  def create(principal, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(principal, nil, attrs, [operation: "project.create"], fn ctx ->
      Commands.operator!(principal)
      project = %Project{state: "active"} |> changeset(attrs) |> Commands.insert!()

      Events.append!(project.id, "project.created", ctx, "project", project.id, %{},
        current: project
      )

      Projection.project(project)
    end)
  end

  def update(principal, id, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      id,
      attrs,
      [operation: "project.update", roles: ["manager"]],
      fn ctx ->
        Commands.expect!(ctx.project, attrs)
        if ctx.project.state not in ~w(active paused), do: Commands.fail!(:invalid_transition)

        if map_size(ctx.project.migration_metadata) > 0 && Map.has_key?(attrs, "name") &&
             attrs["name"] != ctx.project.name,
           do: Commands.fail!(:conflict, %{reason: "legacy_field_frozen", field: "name"})

        project =
          ctx.project
          |> changeset(attrs)
          |> put_change(:version, ctx.project.version + 1)
          |> Commands.update!()

        Events.append!(id, "project.updated", ctx, "project", id, %{},
          previous: ctx.project,
          current: project
        )

        Projection.project(project)
      end
    )
  end

  def transition(principal, id, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      id,
      attrs,
      [operation: "project.transition", roles: ["manager"]],
      fn ctx ->
        Commands.expect!(ctx.project, attrs)
        state = attrs["state"]

        valid =
          {ctx.project.state, state} in [
            {"active", "paused"},
            {"paused", "active"},
            {"active", "archived"},
            {"paused", "archived"}
          ]

        restore = ctx.project.state == "archived" && state == "paused"
        if restore, do: validate_restore!(principal, attrs)
        if !valid && !restore, do: Commands.fail!(:invalid_transition)
        if state == "archived", do: require_resolved_execution!(id)

        project =
          ctx.project
          |> change(state: state, version: ctx.project.version + 1)
          |> Commands.update!()

        Events.append!(id, "project.state_changed", ctx, "project", id, %{},
          previous: ctx.project,
          current: project
        )

        Projection.project(project)
      end
    )
  end

  defp validate_restore!(principal, attrs) do
    Commands.operator!(principal)

    if !is_binary(attrs["reason"]) || String.trim(attrs["reason"]) == "",
      do: Commands.fail!(:invalid)
  end

  defp require_resolved_execution!(id) do
    unresolved =
      Repo.exists?(
        from a in "task_attempts",
          where:
            a.project_id == type(^id, :binary_id) and
              (a.state in ["leased", "running"] or not a.effects_resolved)
      )

    if unresolved, do: Commands.fail!(:conflict, %{reason: "unresolved_execution"})
  end

  def get(principal, id) do
    Commands.read(principal, id, @read_roles, fn ctx -> Projection.project(ctx.project) end)
  end

  def list(principal, params \\ %{}) do
    Commands.read(
      principal,
      nil,
      if(principal.kind == :agent, do: [:credential], else: []),
      fn _ ->
        if principal.kind == :agent && !principal.connection_id, do: Commands.fail!(:unauthorized)
        {limit, offset} = Params.page(params)

        query =
          if principal.kind == :operator do
            from(p in Project)
          else
            from p in Project,
              join: m in ProjectAgent,
              on: m.project_id == p.id,
              where:
                m.agent_id == ^principal.agent_id and m.enabled and
                  fragment("cardinality(?) > 0", m.roles)
          end

        data = Repo.all(from p in query, order_by: p.id, limit: ^limit, offset: ^offset)
        %{"data" => Enum.map(data, &Projection.project/1), "limit" => limit, "offset" => offset}
      end
    )
  end

  def put_member(principal, id, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      id,
      attrs,
      [operation: "project.member", agent_ids: [attrs["agent_id"]]],
      fn ctx ->
        Commands.operator!(principal)
        Commands.expect!(ctx.project, attrs)

        if !Params.uuid?(attrs["agent_id"]) || !Repo.get(Samgita.Domain.Agent, attrs["agent_id"]),
          do: Commands.fail!(:not_found)

        member =
          Repo.get_by(ProjectAgent, project_id: id, agent_id: attrs["agent_id"]) ||
            %ProjectAgent{project_id: id, agent_id: attrs["agent_id"]}

        previous = if member.id, do: member

        changeset =
          member
          |> cast(attrs, [:roles, :enabled])
          |> validate_required([:roles])
          |> validate_subset(:roles, @read_roles)
          |> put_change(:version, if(member.id, do: member.version + 1, else: 1))

        member = if member.id, do: Commands.update!(changeset), else: Commands.insert!(changeset)
        project = ctx.project |> change(version: ctx.project.version + 1) |> Commands.update!()

        Events.append!(
          id,
          "project.membership_changed",
          ctx,
          "project_agent",
          member.id,
          %{
            "agent_id" => member.agent_id,
            "roles" => member.roles,
            "enabled" => member.enabled,
            "project_before" => Events.snapshot(ctx.project),
            "project_after" => Events.snapshot(project)
          },
          previous: previous,
          current: member
        )

        Map.put(Projection.member(member), "project_version", project.version)
      end
    )
  end

  def context(principal, id, params \\ %{}) do
    Commands.read(principal, id, @read_roles, fn ctx ->
      {limit, offset} = Params.page(params)

      roles =
        if principal.kind == :operator,
          do: @read_roles,
          else: Repo.get_by!(ProjectAgent, project_id: id, agent_id: principal.agent_id).roles

      tasks =
        Repo.all(
          from t in Samgita.Domain.Task,
            where: t.project_id == ^id,
            order_by: t.id,
            limit: ^limit,
            offset: ^offset
        )

      members =
        Repo.all(from m in ProjectAgent, where: m.project_id == ^id, order_by: m.id, limit: 100)

      routing =
        Repo.one(
          from s in Samgita.Domain.EventSubscription,
            where: s.project_id == ^id and s.purpose == "responsible" and s.enabled
        )

      event_operations =
        if routing && principal.kind == :agent && routing.agent_id == principal.agent_id &&
             "manager" in roles,
           do: ~w(event.report events.ack_cursor),
           else: []

      %{
        "project" => Projection.project(ctx.project),
        "memberships" => Enum.map(members, &Projection.member/1),
        "repositories" => Samgita.Repositories.list_locked(id),
        "tasks" => Enum.map(tasks, &Projection.task/1),
        "event_routing" => if(routing, do: Events.subscription_projection(routing)),
        "allowed_operations" => allowed_operations(roles, ctx.project.state) ++ event_operations,
        "limit" => limit,
        "offset" => offset
      }
    end)
  end

  defp allowed_operations(roles, state) do
    ~w(context.read events.read deliveries.read schedules.read) ++
      if("manager" in roles && state in ~w(active paused),
        do:
          ~w(project.update project.transition task.create task.update task.transition repository.associate event.trigger),
        else: []
      ) ++
      if("worker" in roles && state in ~w(active paused),
        do:
          ~w(attempt.renew attempt.progress attempt.report attempt.rebind attempt.resolve attempt.proof),
        else: []
      ) ++
      if("worker" in roles && state == "active", do: ~w(attempt.claim attempt.start), else: []) ++
      if "reviewer" in roles && state in ~w(active paused),
        do: ~w(task.review task.accept),
        else: []
  end

  defp changeset(project, attrs),
    do:
      project
      |> cast(attrs, [:name, :description])
      |> validate_required([:name])
      |> validate_length(:name, min: 1, max: 200)
      |> validate_length(:description, max: 20_000)
end
