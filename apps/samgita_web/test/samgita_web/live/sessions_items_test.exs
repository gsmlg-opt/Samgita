defmodule SamgitaWeb.SessionsItemsTest do
  use ExUnit.Case, async: true
  alias SamgitaWeb.SessionsLive.Items

  test "work before a Codex reply is grouped with it; trailing work forms a reply without text" do
    items = [
      %{"id" => "u1", "kind" => "user", "text" => "Fix it"},
      %{"id" => "r1", "kind" => "reasoning", "text" => "Look at the build"},
      %{"id" => "c1", "kind" => "command", "command" => "mix test", "status" => "completed"},
      %{"id" => "a1", "kind" => "agent", "text" => "Fixed."},
      %{"id" => "u2", "kind" => "user", "text" => "Run it again"},
      %{"id" => "c2", "kind" => "command", "command" => "mix test", "status" => "inProgress"}
    ]

    assert [
             %{kind: :user, item: %{"id" => "u1"}},
             %{kind: :agent, id: "a1", text: "Fixed.", work: [%{"id" => "r1"}, %{"id" => "c1"}]},
             %{kind: :user, item: %{"id" => "u2"}},
             %{kind: :agent, id: "work-c2", text: nil, work: [%{"id" => "c2"}]}
           ] = Items.rows(items)
  end
end
