defmodule SamgitaMemory.PRD.Execution do
  @moduledoc "Ecto schema for PRD execution tracking."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @statuses [:not_started, :in_progress, :paused, :blocked, :completed]

  schema "sm_prd_executions" do
    field :prd_ref, :string
    field :prd_hash, :string
    field :title, :string
    field :status, Ecto.Enum, values: @statuses, default: :not_started

    field :progress, :map,
      default: %{
        "completed" => [],
        "in_progress" => [],
        "blocked" => [],
        "not_started" => []
      }

    has_many :events, SamgitaMemory.PRD.Event, foreign_key: :execution_id
    has_many :decisions, SamgitaMemory.PRD.Decision, foreign_key: :execution_id

    timestamps(type: :utc_datetime)
  end

  def changeset(execution, attrs) do
    execution
    |> cast(attrs, [:prd_ref, :prd_hash, :title, :status, :progress])
    |> validate_required([:prd_ref])
    |> unique_constraint(:prd_ref)
  end

  def statuses, do: @statuses
end
