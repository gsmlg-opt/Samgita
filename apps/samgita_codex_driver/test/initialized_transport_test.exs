defmodule SamgitaCodexDriver.InitializedTransportTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.InitializedFixture

  @moduletag :real_codex
  @moduletag timeout: 60_000

  setup {InitializedFixture, :setup}

  for transport <- [:stdio, :websocket, :unix_socket], negotiation <- [:absent, false, true] do
    @tag transport: transport, negotiation: negotiation
    test "initialized has no readiness or acknowledgement effect over #{transport}, negotiation=#{negotiation}",
         context do
      connection = InitializedFixture.open(context, context.transport)
      module = connection.module
      state = InitializedFixture.notify(module, connection.state, %{"method" => "initialized"})

      {response, state} = InitializedFixture.read(module, state, "before-initialize")

      assert response == %{
               "id" => "before-initialize",
               "error" => %{"code" => -32_600, "message" => "Not initialized"}
             }

      {response, state} = InitializedFixture.initialize(module, state, context.negotiation)

      assert %{
               "id" => "initialize",
               "result" => %{"platformOs" => "linux", "codexHome" => codex_home}
             } = response

      assert codex_home == context.codex_home

      # This read deliberately precedes the post-initialize notification.
      state = InitializedFixture.assert_read(module, state, "without-notification")

      notifications = [
        %{"method" => "initialized"},
        %{"method" => "initialized", "params" => nil},
        %{"method" => "initialized", "params" => %{}},
        %{"method" => "initialized", "params" => []},
        %{"method" => "initialized", "params" => "Synthetic scalar"},
        %{"method" => "initialized", "params" => 42},
        %{"method" => "initialized", "params" => false},
        %{
          "method" => "initialized",
          "params" => %{"nested" => [nil, %{"text" => "é🙂"}]},
          "future" => %{"preservedByClient" => [nil, true]}
        },
        %{"method" => "initialized"},
        %{"method" => "initialized"}
      ]

      state =
        notifications
        |> Enum.with_index()
        |> Enum.reduce(state, fn {notification, index}, state ->
          state = InitializedFixture.notify(module, state, notification)
          InitializedFixture.assert_read(module, state, "after-notification-#{index}")
        end)

      state = InitializedFixture.assert_quiet(module, state)
      assert :ok = module.close(state)
      InitializedFixture.assert_borrowed_survival(connection, context.negotiation)
      InitializedFixture.close_owner(connection)
    end
  end
end
