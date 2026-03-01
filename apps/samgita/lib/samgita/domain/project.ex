defmodule Samgita.Domain.Project do
  @moduledoc "Ecto schema for projects with phase tracking and status management."

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

    belongs_to :active_prd, Samgita.Domain.Prd

    timestamps(type: :utc_datetime)
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :git_url, :working_path, :prd_content, :phase, :status, :config, :active_prd_id])
    |> validate_required([:name, :git_url])
    |> validate_git_url()
    |> unique_constraint(:git_url)
  end

  defp validate_git_url(changeset) do
    validate_change(changeset, :git_url, fn :git_url, url ->
      # Allow git@, https://, http:// URLs or local paths for development
      cond do
        String.starts_with?(url, "/") ->
          []

        String.match?(url, ~r/^(git@|https?:\/\/).+/) ->
          []

        true ->
          [git_url: "must be a valid git URL (git@..., https://..., or local path)"]
      end
    end)
  end

  def phases, do: @phases
  def statuses, do: @statuses
end
