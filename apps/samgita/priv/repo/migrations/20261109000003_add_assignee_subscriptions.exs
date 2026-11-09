defmodule Samgita.Repo.Migrations.AddAssigneeSubscriptions do
  use Ecto.Migration

  # Design §10: at most one enabled assignee-notification subscription per
  # executor Agent in a Project. Responsible routing is unchanged.
  def change do
    create unique_index(:event_subscriptions, [:project_id, :agent_id],
             name: :one_assignee_subscription_per_agent,
             where: "purpose = 'assignee' AND enabled"
           )
  end
end
