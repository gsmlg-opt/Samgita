defmodule Samgita.Events do
  @moduledoc "Transaction-local audit events and delivery intents. No network dispatcher."
  import Ecto.Query
  alias Samgita.{Commands, Repo}
  alias Samgita.Domain.{DomainEvent, EventDelivery, EventSubscription, Project}

  def append!(
        project_id,
        type,
        %{principal: principal, command_id: command_id},
        resource_type,
        resource_id,
        data \\ %{},
        states \\ []
      ) do
    if !Repo.in_transaction?(), do: raise("events require an aggregate transaction")

    sequence =
      if project_id do
        {1, [sequence]} =
          Repo.update_all(
            from(p in Project, where: p.id == ^project_id, select: p.event_sequence),
            inc: [event_sequence: 1]
          )

        sequence
      end

    event =
      %DomainEvent{}
      |> Ecto.Changeset.change(
        project_id: project_id,
        sequence: sequence,
        type: type,
        actor: Commands.actor_key(principal),
        command_id: command_id,
        resource_type: resource_type,
        resource_id: resource_id,
        data: data,
        before_state: snapshot(Keyword.get(states, :previous)),
        after_state: snapshot(Keyword.get(states, :current)),
        created_at: DateTime.utc_now()
      )
      |> Repo.insert!()

    if project_id do
      Repo.all(from s in EventSubscription, where: s.project_id == ^project_id and s.enabled)
      |> Enum.filter(&(&1.types == [] || type in &1.types))
      |> Enum.each(fn subscription ->
        %EventDelivery{}
        |> Ecto.Changeset.change(
          event_id: event.id,
          subscription_id: subscription.id,
          subscription_revision: subscription.revision,
          state: "pending"
        )
        |> Repo.insert!()
      end)
    end

    event
  end

  def snapshot(nil), do: nil

  def snapshot(record) do
    Map.take(record, [
      :state,
      :version,
      :enabled,
      :generation,
      :owner,
      :admission_open,
      :epoch,
      :adopted,
      :execution_hold
    ])
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end
end
