defmodule SamgitaWeb.WebhookJSON do
  alias Samgita.Domain.Webhook

  def index(%{webhooks: webhooks}) do
    %{data: for(webhook <- webhooks, do: data(webhook))}
  end

  def show(%{webhook: webhook}) do
    %{data: data(webhook)}
  end

  defp data(%Webhook{} = webhook) do
    %{
      id: webhook.id,
      url: webhook.url,
      events: webhook.events,
      active: webhook.active,
      inserted_at: webhook.inserted_at
    }
  end
end
