defmodule SamgitaProtocol.Event do
  @moduledoc "Original event identity and timestamp survive every delivery attempt."
  alias SamgitaProtocol.{Error, Schema}

  def validate(event) do
    {required, optional} = Schema.event_fields()

    with :ok <- Schema.shape(event, required, optional, "invalid_params"),
         :ok <- Schema.references(event),
         do: :ok
  end

  def retry(event, delivery_attempt_id) do
    with :ok <- validate(event),
         true <-
           Schema.valid?(delivery_attempt_id, :id) and
             delivery_attempt_id != event["delivery_attempt_id"] do
      {:ok, Map.put(event, "delivery_attempt_id", delivery_attempt_id)}
    else
      false -> {:error, Error.new("invalid_params")}
      {:error, _} = error -> error
    end
  end

  def same?(a, b),
    do: Map.delete(a, "delivery_attempt_id") == Map.delete(b, "delivery_attempt_id")
end
