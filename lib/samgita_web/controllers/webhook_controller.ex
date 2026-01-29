defmodule SamgitaWeb.WebhookController do
  use SamgitaWeb, :controller

  alias Samgita.Webhooks
  alias Samgita.Domain.Webhook

  action_fallback SamgitaWeb.FallbackController

  def index(conn, _params) do
    webhooks = Webhooks.list_webhooks()
    render(conn, :index, webhooks: webhooks)
  end

  def create(conn, %{"webhook" => params}) do
    with {:ok, %Webhook{} = webhook} <- Webhooks.create_webhook(params) do
      conn
      |> put_status(:created)
      |> render(:show, webhook: webhook)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, _} <- Webhooks.delete_webhook(id) do
      send_resp(conn, :no_content, "")
    end
  end
end
