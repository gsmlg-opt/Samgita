defmodule SamgitaProtocol.Replay do
  @moduledoc "A bounded host-owned replay log. Retention loss is a gap, never silent success. Not durable storage."
  alias SamgitaProtocol.{Error, Schema}
  defstruct [:stream_id, limit: 128, next_cursor: 1, events: []]

  def new(stream_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 128)

    if Schema.valid?(stream_id, :id) and is_integer(limit) and limit in 1..10_000,
      do: {:ok, %__MODULE__{stream_id: stream_id, limit: limit}},
      else: {:error, Error.new("invalid_params")}
  end

  def append(log, notification) when is_map(notification) and not is_struct(notification) do
    message =
      Map.merge(notification, %{"stream_id" => log.stream_id, "cursor" => log.next_cursor})

    case if Map.has_key?(notification, "stream_id") or Map.has_key?(notification, "cursor"),
           do: {:error, Error.new("invalid_message")},
           else: Schema.validate(message) do
      {:ok, %{"type" => "notification"}} ->
        events = Enum.take(log.events ++ [message], -log.limit)
        {:ok, message, %{log | next_cursor: log.next_cursor + 1, events: events}}

      _ ->
        {:error, Error.new("invalid_message")}
    end
  end

  def append(_, _), do: {:error, Error.new("invalid_message")}

  def since(log, cursor) when is_integer(cursor) and cursor >= 0 do
    oldest =
      case log.events do
        [first | _] -> first["cursor"]
        [] -> log.next_cursor
      end

    if cursor < oldest - 1 or cursor >= log.next_cursor,
      do:
        {:error,
         Error.new("replay_gap", %{
           "earliest_cursor" => oldest - 1,
           "latest_cursor" => log.next_cursor - 1
         })},
      else: {:ok, log.events |> Enum.filter(&(&1["cursor"] > cursor)) |> Enum.take(128)}
  end

  def since(_, _), do: {:error, Error.new("invalid_params")}
end
