defmodule Samgita.GitHub.PatCleanup do
  @moduledoc "Periodic removal of closed items from the local GitHub console cache."
  import Ecto.Query
  alias Samgita.Domain.{GitHubPatConnection, GitHubPatItem}
  alias Samgita.Repo

  @interval_days 15

  def run_due(now \\ DateTime.utc_now()) do
    Repo.transact(fn ->
      due = from c in GitHubPatConnection, where: c.next_cleanup_at <= ^now, lock: "FOR UPDATE"

      case Repo.one(due) do
        nil ->
          {:ok, 0}

        connection ->
          closed =
            from i in GitHubPatItem,
              where: i.connection_id == ^connection.id and i.state in ["closed", "merged"]

          {deleted, _} = Repo.delete_all(closed)

          # Keep the original 15-day cadence even after a delayed tick or downtime.
          intervals =
            1 + div(DateTime.diff(now, connection.next_cleanup_at, :day), @interval_days)

          next = DateTime.add(connection.next_cleanup_at, intervals * @interval_days, :day)
          Repo.update!(Ecto.Changeset.change(connection, next_cleanup_at: next))
          {:ok, deleted}
      end
    end)
  end
end
