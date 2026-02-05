defmodule Samgita.Prds do
  @moduledoc """
  Context module for PRD (Product Requirements Document) management.
  """

  import Ecto.Query
  alias Samgita.Domain.{Prd, ChatMessage}
  alias Samgita.Repo

  ## PRD Functions

  def list_prds(project_id) do
    Prd
    |> where(project_id: ^project_id)
    |> order_by(desc: :updated_at)
    |> Repo.all()
  end

  def get_prd(id) do
    case Repo.get(Prd, id) do
      nil -> {:error, :not_found}
      prd -> {:ok, prd}
    end
  end

  def get_prd!(id), do: Repo.get!(Prd, id)

  def get_prd_with_messages(id) do
    case Repo.get(Prd, id) do
      nil ->
        {:error, :not_found}

      prd ->
        messages =
          ChatMessage
          |> where(prd_id: ^id)
          |> order_by(asc: :inserted_at)
          |> Repo.all()

        {:ok, %{prd | chat_messages: messages}}
    end
  end

  def create_prd(attrs) do
    %Prd{}
    |> Prd.changeset(attrs)
    |> Repo.insert()
  end

  def update_prd(%Prd{} = prd, attrs) do
    prd
    |> Prd.changeset(attrs)
    |> Repo.update()
  end

  def delete_prd(%Prd{} = prd) do
    Repo.delete(prd)
  end

  ## Chat Message Functions

  def list_messages(prd_id) do
    ChatMessage
    |> where(prd_id: ^prd_id)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  def create_message(attrs) do
    %ChatMessage{}
    |> ChatMessage.changeset(attrs)
    |> Repo.insert()
  end

  def add_user_message(prd_id, content) do
    create_message(%{
      prd_id: prd_id,
      role: :user,
      content: content
    })
  end

  def add_assistant_message(prd_id, content) do
    create_message(%{
      prd_id: prd_id,
      role: :assistant,
      content: content
    })
  end

  def add_system_message(prd_id, content) do
    create_message(%{
      prd_id: prd_id,
      role: :system,
      content: content
    })
  end

  ## PRD Generation

  def generate_prd_content(prd_id) do
    with {:ok, prd} <- get_prd_with_messages(prd_id) do
      # Extract all assistant messages and combine them
      content =
        prd.chat_messages
        |> Enum.filter(&(&1.role == :assistant))
        |> Enum.map(& &1.content)
        |> Enum.join("\n\n---\n\n")

      update_prd(prd, %{content: content})
    end
  end
end
