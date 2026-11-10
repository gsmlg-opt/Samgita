defmodule SamgitaWeb.SessionsItemsTest do
  use ExUnit.Case, async: true
  alias SamgitaWeb.SessionsLive.Items

  test "work before a Codex reply is grouped with it; trailing work forms a reply without text" do
    items = [
      %{"id" => "u1", "kind" => "user", "text" => "Fix it"},
      %{"id" => "r1", "kind" => "reasoning", "text" => "Look at the build"},
      %{"id" => "r0", "kind" => "reasoning", "text" => ""},
      %{
        "id" => "c1",
        "kind" => "command",
        "command" => "mix test",
        "status" => "completed",
        "exit_code" => 0,
        "output" => "ok\n"
      },
      %{"id" => "a1", "kind" => "agent", "text" => "Fixed."},
      %{"id" => "u2", "kind" => "user", "text" => "Run it again"},
      %{"id" => "c2", "kind" => "command", "command" => "mix test", "status" => "inProgress"}
    ]

    # A reply is identified by its first item, so its ID survives its text arriving.
    assert [
             %{kind: :user, item: %{"id" => "u1"}},
             %{
               kind: :agent,
               id: "r1",
               text: "Fixed.",
               work: [%{"id" => "r1"}, %{"id" => "r0"}, %{"id" => "c1"}]
             },
             %{kind: :user, item: %{"id" => "u2"}},
             %{kind: :agent, id: "c2", text: nil, work: [%{"id" => "c2"}]}
           ] = Items.rows(items)

    assert [
             %{"id" => "u1", "role" => "user", "content" => "Fix it"},
             %{
               "id" => "r1",
               "role" => "assistant",
               "content" => "Fixed.",
               "status" => "complete",
               "tools" => [
                 %{"name" => "Reasoning", "result" => %{"text" => ["Look at the build"]}},
                 %{"name" => "mix test", "status" => "success"}
               ]
             },
             %{"id" => "u2"},
             %{
               "id" => "c2",
               "content" => "",
               "status" => "streaming",
               "tools" => [%{"name" => "mix test", "status" => "running", "result" => nil}]
             }
           ] = Items.messages(items, true)
  end
end
