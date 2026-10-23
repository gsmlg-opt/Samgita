defmodule Samgita.Schedules do
  @moduledoc "Revisioned schedules emit facts, with bounded catch-up over absolute UTC minutes."
  import Ecto.Query
  import Ecto.Changeset
  alias Oban.Cron.Expression
  alias Samgita.{Commands, Events, Params, Principal, Projection, Repo}
  alias Samgita.Domain.{PlatformAuthority, Project, Schedule, ScheduleOccurrence, Task}

  @read_roles ~w(observer worker manager reviewer)
  @fields ~w(expression timezone event_type payload enabled)a
  @projection ~w(id project_id expression timezone event_type payload enabled revision version scanned_through inserted_at updated_at)a

  def create(principal, project_id, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(principal, project_id, attrs, [operation: "schedule.create"], fn ctx ->
      Commands.operator!(principal)
      require_project!(ctx.project)

      schedule =
        %Schedule{project_id: project_id, scanned_through: cursor!(attrs)}
        |> changeset(attrs)
        |> validate_references!(project_id)
        |> Commands.insert!()

      Events.append!(
        project_id,
        "schedule.created",
        Map.put(ctx, :notify, false),
        "schedule",
        schedule.id,
        %{"revision" => schedule.revision},
        current: schedule
      )

      project(schedule)
    end)
  end

  def update(principal, project_id, id, attrs) do
    attrs = Params.strings(attrs)

    id =
      case Ecto.UUID.cast(id) do
        {:ok, canonical} -> canonical
        :error -> id
      end

    Commands.run(
      principal,
      project_id,
      attrs,
      [operation: "schedule.update", target: id],
      fn ctx ->
        Commands.operator!(principal)
        require_project!(ctx.project)
        schedule = get_locked!(project_id, id)
        Commands.expect!(schedule, attrs)

        current =
          schedule
          |> changeset(attrs)
          |> validate_references!(project_id)
          |> change(
            revision: schedule.revision + 1,
            version: schedule.version + 1,
            scanned_through: cursor!(attrs)
          )
          |> Commands.update!()

        Events.append!(
          project_id,
          "schedule.updated",
          Map.put(ctx, :notify, false),
          "schedule",
          id,
          %{
            "revision" => current.revision,
            "previous_cursor" => DateTime.to_iso8601(schedule.scanned_through),
            "cursor" => DateTime.to_iso8601(current.scanned_through)
          },
          previous: schedule,
          current: current
        )

        project(current)
      end
    )
  end

  def list(principal, project_id, params \\ %{}) do
    Commands.read(principal, project_id, @read_roles, fn _ ->
      {limit, offset} = Params.page(params)

      schedules =
        Repo.all(
          from s in Schedule,
            where: s.project_id == ^project_id,
            order_by: s.id,
            limit: ^limit,
            offset: ^offset
        )

      %{"data" => Enum.map(schedules, &project/1), "limit" => limit, "offset" => offset}
    end)
  end

  @doc """
  Scan a bounded number of UTC minutes. Missed real occurrences remain behind the durable cursor.
  A repeated local minute during DST is evaluated twice; a nonexistent local minute is never seen.
  """
  def tick(opts \\ []) do
    now = floor_minute(Keyword.get(opts, :now, DateTime.utc_now()))
    schedule_limit = bound(opts, :max_schedules, 100, 100)
    minute_limit = bound(opts, :max_minutes, 1440, 1440)
    occurrence_limit = bound(opts, :max_occurrences, 100, 100)

    schedules =
      Repo.all(
        from s in Schedule,
          join: p in Project,
          on: p.id == s.project_id,
          where: s.enabled and p.state == "active" and s.scanned_through < ^now,
          order_by: [asc: s.scanned_through, asc: s.id],
          limit: ^schedule_limit,
          select: %{id: s.id, project_id: s.project_id}
      )

    Enum.reduce_while(schedules, {:ok, empty_stats()}, fn candidate, stats ->
      scan_candidate(candidate, stats, now, minute_limit, occurrence_limit)
    end)
  end

  defp scan_candidate(candidate, {:ok, stats}, now, minute_limit, occurrence_limit) do
    case scan(candidate, now, minute_limit, occurrence_limit) do
      {:ok, result} ->
        current = %{
          "scanned" => stats["scanned"] + result["scanned"],
          "emitted" => stats["emitted"] + result["emitted"],
          "schedules" => stats["schedules"] + result["schedules"],
          "closed" => stats["closed"] || result["closed"]
        }

        if current["closed"], do: {:halt, {:ok, current}}, else: {:cont, {:ok, current}}

      {:error, _} = error ->
        {:halt, error}
    end
  end

  defp scan(candidate, now, minute_limit, occurrence_limit) do
    Commands.transaction(fn ->
      authority = Repo.one!(from a in PlatformAuthority, where: a.id == 1, lock: "FOR SHARE")

      if authority.owner != "hub" || !authority.admission_open do
        Map.put(empty_stats(), "closed", true)
      else
        scan_open_project(candidate, now, minute_limit, occurrence_limit)
      end
    end)
  end

  defp scan_open_project(candidate, now, minute_limit, occurrence_limit) do
    project =
      Repo.one!(from p in Project, where: p.id == ^candidate.project_id, lock: "FOR UPDATE")

    schedule = get_locked!(candidate.project_id, candidate.id)

    if project.state != "active" || !schedule.enabled ||
         DateTime.compare(schedule.scanned_through, now) != :lt do
      empty_stats()
    else
      {:ok, expression} = Expression.parse(schedule.expression)
      scan_minutes(schedule, expression, now, minute_limit, occurrence_limit)
    end
  end

  defp scan_minutes(schedule, expression, now, minute_limit, occurrence_limit) do
    {cursor, scanned, emitted} =
      Enum.reduce_while(1..minute_limit, {schedule.scanned_through, 0, 0}, fn _, acc ->
        scan_minute(schedule, expression, now, occurrence_limit, acc)
      end)

    schedule |> change(scanned_through: cursor) |> Commands.update!()
    %{"scanned" => scanned, "emitted" => emitted, "schedules" => 1, "closed" => false}
  end

  defp scan_minute(schedule, expression, now, occurrence_limit, {cursor, scanned, emitted}) do
    due_at = DateTime.add(cursor, 60, :second)

    if DateTime.compare(due_at, now) == :gt || emitted >= occurrence_limit do
      {:halt, {cursor, scanned, emitted}}
    else
      {:ok, local_time} =
        DateTime.shift_zone(due_at, schedule.timezone, Tzdata.TimeZoneDatabase)

      count =
        if Expression.now?(expression, local_time) do
          emit_occurrence!(schedule, due_at)
        else
          0
        end

      {:cont, {due_at, scanned + 1, emitted + count}}
    end
  end

  defp emit_occurrence!(schedule, due_at) do
    existing =
      Repo.get_by(ScheduleOccurrence,
        schedule_id: schedule.id,
        revision: schedule.revision,
        due_at: due_at
      )

    if existing do
      0
    else
      validate_task_reference!(schedule.project_id, schedule.payload)
      occurrence_id = Ecto.UUID.generate()

      data = %{
        "schedule_id" => schedule.id,
        "schedule_revision" => schedule.revision,
        "due_at" => DateTime.to_iso8601(due_at),
        "payload" => schedule.payload
      }

      data =
        if schedule.payload["task_id"],
          do: Map.put(data, "task_id", schedule.payload["task_id"]),
          else: data

      event =
        Events.append!(
          schedule.project_id,
          schedule.event_type,
          %{
            principal: Principal.operator(),
            command_id: occurrence_id,
            source: "schedule",
            source_id: occurrence_id,
            correlation_id: occurrence_id
          },
          "schedule",
          schedule.id,
          data
        )

      %ScheduleOccurrence{}
      |> change(
        id: occurrence_id,
        project_id: schedule.project_id,
        schedule_id: schedule.id,
        revision: schedule.revision,
        due_at: due_at,
        event_id: event.id
      )
      |> Commands.insert!()

      1
    end
  end

  defp changeset(schedule, attrs) do
    schedule
    |> cast(attrs, @fields)
    |> validate_required([:expression, :timezone, :event_type, :payload, :enabled])
    |> validate_inclusion(:event_type, ["schedule.check"])
    |> validate_change(:expression, fn field, value ->
      if valid_expression?(value), do: [], else: [{field, "must be a five-field cron expression"}]
    end)
    |> validate_change(:timezone, fn field, value ->
      if valid_timezone?(value), do: [], else: [{field, "must be a known IANA timezone"}]
    end)
    |> validate_change(:payload, fn field, value ->
      if Events.validate_payload(value) == :ok,
        do: [],
        else: [{field, "must be safe event metadata"}]
    end)
  end

  defp valid_expression?(value) when is_binary(value) do
    byte_size(value) <= 100 && Regex.match?(~r/\A[0-9*\/,\- ]+\z/, value) &&
      length(String.split(value)) == 5 && match?({:ok, _}, Expression.parse(value))
  end

  defp valid_expression?(_), do: false

  defp valid_timezone?(value) when is_binary(value) do
    byte_size(value) <= 100 &&
      match?({:ok, _}, DateTime.shift_zone(DateTime.utc_now(), value, Tzdata.TimeZoneDatabase))
  end

  defp valid_timezone?(_), do: false

  defp validate_references!(changeset, project_id) do
    if changeset.valid?, do: validate_task_reference!(project_id, get_field(changeset, :payload))
    changeset
  end

  defp validate_task_reference!(project_id, %{"task_id" => id}) do
    if !Params.uuid?(id) ||
         !Repo.exists?(from t in Task, where: t.id == ^id and t.project_id == ^project_id),
       do: Commands.fail!(:not_found)

    :ok
  end

  defp validate_task_reference!(_, _), do: :ok

  defp cursor!(attrs) do
    case attrs["start_at"] do
      nil ->
        floor_minute(DateTime.utc_now())

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, 0} -> floor_minute(datetime)
          _ -> Commands.fail!(:invalid, %{field: "start_at"})
        end

      _ ->
        Commands.fail!(:invalid, %{field: "start_at"})
    end
  end

  defp floor_minute(%DateTime{} = datetime) do
    utc = DateTime.shift_zone!(datetime, "Etc/UTC")
    %{utc | second: 0, microsecond: {0, 6}}
  end

  defp bound(opts, key, default, maximum) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) -> min(max(value, 1), maximum)
      _ -> default
    end
  end

  defp get_locked!(project_id, id) do
    if !Params.uuid?(id), do: Commands.fail!(:not_found)

    Repo.one(
      from s in Schedule, where: s.project_id == ^project_id and s.id == ^id, lock: "FOR UPDATE"
    ) ||
      Commands.fail!(:not_found)
  end

  defp require_project!(%{state: state}) when state in ~w(active paused), do: :ok
  defp require_project!(_), do: Commands.fail!(:invalid_transition)
  defp project(schedule), do: Projection.fields(schedule, @projection)
  defp empty_stats, do: %{"scanned" => 0, "emitted" => 0, "schedules" => 0, "closed" => false}
end
