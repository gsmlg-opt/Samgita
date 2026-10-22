defmodule Samgita.Domain.ScheduleOccurrence do
  @moduledoc false
  use Samgita.Schema

  schema "schedule_occurrences" do
    field :schedule_id, :binary_id
    field :project_id, :binary_id
    field :revision, :integer
    field :due_at, :utc_datetime_usec
    field :event_id, :binary_id
    timestamps()
  end
end
