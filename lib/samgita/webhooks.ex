defmodule Samgita.Webhooks do
  @moduledoc """
  Context for webhook management and event dispatch.
  """

  import Ecto.Query
  alias Samgita.Repo
  alias Samgita.Domain.Webhook

  def list_webhooks do
    Webhook |> order_by(desc: :inserted_at) |> Repo.all()
  end

  def get_webhook(id) do
    case Repo.get(Webhook, id) do
      nil -> {:error, :not_found}
      webhook -> {:ok, webhook}
    end
  end

  def create_webhook(attrs) do
    %Webhook{}
    |> Webhook.changeset(attrs)
    |> Repo.insert()
  end

  def delete_webhook(id) do
    case get_webhook(id) do
      {:ok, webhook} -> Repo.delete(webhook)
      error -> error
    end
  end

  def dispatch(event, payload) do
    Webhook
    |> where(active: true)
    |> Repo.all()
    |> Enum.filter(&(event in &1.events))
    |> Enum.each(fn webhook ->
      Oban.insert(
        Samgita.Workers.WebhookWorker.new(%{
          webhook_id: webhook.id,
          event: event,
          payload: payload
        })
      )
    end)
  end
end
