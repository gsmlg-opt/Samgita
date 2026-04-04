defmodule Samgita.Agent.Claude do
  @moduledoc """
  Claude integration delegating to SamgitaProvider.
  Keeps `backoff_ms/1` for the agent worker retry logic.
  """

  @max_backoff_ms 3_600_000

  def chat(prompt, opts \\ []) do
    SamgitaProvider.query(prompt, opts)
  end

  def start_session(system_prompt, opts \\ []) do
    SamgitaProvider.start_session(system_prompt, opts)
  end

  def send_message(session, message) do
    SamgitaProvider.send_message(session, message)
  end

  def close_session(session) do
    SamgitaProvider.close_session(session)
  end

  def backoff_ms(attempt) do
    min((60_000 * :math.pow(2, attempt)) |> round(), @max_backoff_ms)
  end
end
