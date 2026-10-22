defmodule Samgita.Domain.Schedule do
  @moduledoc false
  use Samgita.Schema

  schema "event_schedules" do
    field :project_id, :binary_id
    field :expression, :string
    field :timezone, :string, default: "Etc/UTC"
    field :event_type, :string, default: "schedule.check"
    field :payload, :map, default: %{}
    field :enabled, :boolean, default: true
    field :revision, :integer, default: 1
    field :version, :integer, default: 1
    field :scanned_through, :utc_datetime_usec
    timestamps()
  end
end
