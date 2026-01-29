defmodule Samgita.Domain.Artifact do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @types [:code, :doc, :config, :deployment]

  schema "artifacts" do
    field :type, Ecto.Enum, values: @types
    field :path, :string
    field :content, :string
    field :content_hash, :string
    field :metadata, :map, default: %{}

    belongs_to :project, Samgita.Domain.Project
    belongs_to :task, Samgita.Domain.Task

    timestamps(type: :utc_datetime)
  end

  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [:type, :path, :content, :content_hash, :metadata, :project_id, :task_id])
    |> validate_required([:type, :path, :project_id])
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:task_id)
  end
end
