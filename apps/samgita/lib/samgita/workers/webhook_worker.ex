defmodule Samgita.Workers.WebhookWorker do
  @moduledoc """
  Oban worker that delivers webhook notifications.
  """

  use Oban.Worker,
    queue: :agent_tasks,
    max_attempts: 5

  require Logger

  @impl true
  def perform(%Oban.Job{
        args: %{"webhook_id" => webhook_id, "event" => event, "payload" => payload}
      }) do
    alias Samgita.Domain.Webhook

    case Samgita.Repo.get(Webhook, webhook_id) do
      nil ->
        Logger.warning("Webhook #{webhook_id} not found, discarding")
        :ok

      %Webhook{active: false} ->
        :ok

      webhook ->
        deliver(webhook, event, payload)
    end
  end

  defp deliver(webhook, event, payload) do
    body =
      Jason.encode!(%{
        event: event,
        payload: payload,
        timestamp: DateTime.utc_now()
      })

    headers = [
      {~c"content-type", ~c"application/json"},
      {~c"x-webhook-event", String.to_charlist(event)}
    ]

    headers =
      if webhook.secret do
        signature =
          :crypto.mac(:hmac, :sha256, webhook.secret, body) |> Base.encode16(case: :lower)

        [{~c"x-webhook-signature", String.to_charlist(signature)} | headers]
      else
        headers
      end

    case :httpc.request(
           :post,
           {String.to_charlist(webhook.url), headers, ~c"application/json",
            String.to_charlist(body)},
           [{:timeout, 10_000}],
           []
         ) do
      {:ok, {{_, status, _}, _, _}} when status in 200..299 ->
        Logger.info("Webhook delivered: #{event} -> #{webhook.url} (#{status})")
        :ok

      {:ok, {{_, status, _}, _, _}} ->
        Logger.warning("Webhook failed: #{event} -> #{webhook.url} (#{status})")
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("Webhook error: #{event} -> #{webhook.url} (#{inspect(reason)})")
        {:error, inspect(reason)}
    end
  end
end
