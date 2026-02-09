defmodule SamgitaMemory.PRD do
  @moduledoc "Context module for PRD execution tracking."

  import Ecto.Query

  alias SamgitaMemory.Repo
  alias SamgitaMemory.PRD.{Execution, Event, Decision}
  alias SamgitaMemory.Cache.PRDTable

  @doc """
  Start or resume tracking a PRD execution.
  If an execution exists for this prd_ref, returns it. Otherwise creates new.
  """
  def start_execution(prd_ref, opts \\ []) do
    case Repo.get_by(Execution, prd_ref: prd_ref) do
      nil ->
        attrs = %{
          prd_ref: prd_ref,
          title: Keyword.get(opts, :title),
          status: :in_progress
        }

        %Execution{}
        |> Execution.changeset(attrs)
        |> Repo.insert()

      execution ->
        if execution.status == :not_started do
          execution
          |> Execution.changeset(%{status: :in_progress})
          |> Repo.update()
        else
          {:ok, execution}
        end
    end
  end

  @doc """
  Get current state of a PRD execution with progress and recent events.

  Returns: %{execution: ..., recent_events: [...], decisions: [...]}
  """
  def get_context(prd_id, opts \\ []) do
    event_limit = Keyword.get(opts, :event_limit, 50)

    # Try ETS cache first
    case PRDTable.get(prd_id) do
      {:ok, cached} ->
        {:ok, cached}

      :miss ->
        case Repo.get(Execution, prd_id) do
          nil ->
            {:error, :not_found}

          execution ->
            recent_events =
              Event
              |> where([e], e.execution_id == ^prd_id)
              |> order_by([e], desc: e.inserted_at)
              |> limit(^event_limit)
              |> Repo.all()

            decisions =
              Decision
              |> where([d], d.execution_id == ^prd_id)
              |> order_by([d], desc: d.inserted_at)
              |> Repo.all()

            context = %{
              execution: execution,
              recent_events: recent_events,
              decisions: decisions
            }

            # Cache the result
            PRDTable.put(prd_id, context)

            {:ok, context}
        end
    end
  end

  @doc "Append an event to a PRD execution."
  def append_event(prd_id, event_attrs) do
    attrs = Map.put(event_attrs, :execution_id, prd_id)

    result =
      %Event{}
      |> Event.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, event} ->
        # Invalidate cache so next read gets fresh data
        PRDTable.invalidate(prd_id)
        {:ok, event}

      error ->
        error
    end
  end

  @doc "Record a decision made during PRD execution."
  def record_decision(prd_id, decision_attrs) do
    attrs = Map.put(decision_attrs, :execution_id, prd_id)

    result =
      %Decision{}
      |> Decision.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, decision} ->
        PRDTable.invalidate(prd_id)
        {:ok, decision}

      error ->
        error
    end
  end

  @doc "Update PRD execution status."
  def update_status(prd_id, status) do
    case Repo.get(Execution, prd_id) do
      nil ->
        {:error, :not_found}

      execution ->
        result =
          execution
          |> Execution.changeset(%{status: status})
          |> Repo.update()

        case result do
          {:ok, updated} ->
            PRDTable.invalidate(prd_id)
            {:ok, updated}

          error ->
            error
        end
    end
  end

  @doc "Get a single execution by ID."
  def get_execution(prd_id) do
    Repo.get(Execution, prd_id)
  end

  @doc "Get a single execution by prd_ref."
  def get_execution_by_ref(prd_ref) do
    Repo.get_by(Execution, prd_ref: prd_ref)
  end
end
