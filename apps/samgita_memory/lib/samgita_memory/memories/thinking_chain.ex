defmodule SamgitaMemory.Memories.ThinkingChain do
  @moduledoc "Ecto schema and context for thinking chains — reasoning trace capture and retrieval."

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias SamgitaMemory.Repo

  @primary_key {:id, :binary_id, autogenerate: true}

  @scope_types [:global, :project, :agent]
  @statuses [:active, :completed, :abandoned]

  schema "sm_thinking_chains" do
    field :scope_type, Ecto.Enum, values: @scope_types
    field :scope_id, :string
    field :query, :string
    field :summary, :string
    field :embedding, Pgvector.Ecto.Vector
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :thoughts, {:array, :map}, default: []
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(chain, attrs) do
    chain
    |> cast(attrs, [
      :scope_type,
      :scope_id,
      :query,
      :summary,
      :embedding,
      :status,
      :thoughts,
      :metadata
    ])
    |> validate_required([:scope_type, :query])
  end

  @doc "Start a new thinking chain"
  def start(query, opts \\ []) do
    attrs = %{
      query: query,
      scope_type: Keyword.get(opts, :scope_type, :global),
      scope_id: Keyword.get(opts, :scope_id),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc "Add a thought to an active chain"
  def add_thought(chain_id, thought) do
    case Repo.get(__MODULE__, chain_id) do
      nil ->
        {:error, :not_found}

      chain ->
        thought_entry = Map.merge(thought, %{number: length(chain.thoughts) + 1})

        chain
        |> changeset(%{thoughts: chain.thoughts ++ [thought_entry]})
        |> Repo.update()
    end
  end

  @doc "Complete a chain — triggers summarization and memory extraction"
  def complete(chain_id) do
    case Repo.get(__MODULE__, chain_id) do
      nil ->
        {:error, :not_found}

      chain ->
        case chain |> changeset(%{status: :completed}) |> Repo.update() do
          {:ok, completed_chain} ->
            # Enqueue async summarization
            SamgitaMemory.Workers.Summarize.enqueue_chain_summarization(completed_chain.id)
            {:ok, completed_chain}

          error ->
            error
        end
    end
  end

  @doc "Retrieve similar past thinking chains by scope"
  def recall(_query, opts \\ []) do
    scope_type = Keyword.get(opts, :scope_type)
    scope_id = Keyword.get(opts, :scope_id)
    limit = Keyword.get(opts, :limit, 5)

    __MODULE__
    |> where([c], c.status == :completed)
    |> maybe_filter_scope(scope_type, scope_id)
    |> order_by([c], desc: c.updated_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_filter_scope(query, nil, _), do: query

  defp maybe_filter_scope(query, scope_type, nil),
    do: where(query, [c], c.scope_type == ^scope_type)

  defp maybe_filter_scope(query, scope_type, scope_id) do
    where(query, [c], c.scope_type == ^scope_type and c.scope_id == ^scope_id)
  end

  def scope_types, do: @scope_types
  def statuses, do: @statuses
end
