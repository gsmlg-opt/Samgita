defmodule Samgita.Domain.Project do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @phases [
    :bootstrap,
    :discovery,
    :architecture,
    :infrastructure,
    :development,
    :qa,
    :deployment,
    :business,
    :growth,
    :perpetual
  ]

  @statuses [:pending, :running, :paused, :completed, :failed]

  schema "projects" do
    field :name, :string
    field :git_url, :string
    field :working_path, :string
    field :prd_content, :string
    field :phase, Ecto.Enum, values: @phases, default: :bootstrap
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :config, :map, default: %{}

    has_many :tasks, Samgita.Domain.Task
    has_many :agent_runs, Samgita.Domain.AgentRun
    has_many :artifacts, Samgita.Domain.Artifact
    has_many :memories, Samgita.Domain.Memory
    has_many :snapshots, Samgita.Domain.Snapshot

    timestamps(type: :utc_datetime)
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :git_url, :working_path, :prd_content, :phase, :status, :config])
    |> validate_required([:name, :git_url])
    |> unique_constraint(:git_url)
  end

  def phases, do: @phases
  def statuses, do: @statuses
end
