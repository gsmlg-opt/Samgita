defmodule StandaloneConsumerTest do
  use ExUnit.Case

  test "one logical event survives delivery retries without platform applications or listeners" do
    ports = :erlang.ports() |> MapSet.new()
    sockets = :socket.which_sockets() |> MapSet.new()
    result = StandaloneConsumer.run()
    assert result.event_count == 1
    assert result.received["event_id"] == result.redelivered["event_id"]
    assert result.redelivered["delivery_attempt_id"] == "delivery-2"
    assert result.received["acceptance"] == "received"
    assert result.report["management_acceptance"] == "not_requested"
    assert result.status["processing_status"] == "completed"
    assert result.unsupported_sessions

    for {app, _, _} <- Application.started_applications() do
      refute app in [
               :samgita,
               :samgita_web,
               :samgita_provider,
               :samgita_memory,
               :ecto,
               :ecto_sql,
               :phoenix,
               :backplane,
               :bandit,
               :oban,
               :postgrex
             ]
    end

    assert ports == MapSet.new(:erlang.ports())
    assert sockets == MapSet.new(:socket.which_sockets())
  end
end
