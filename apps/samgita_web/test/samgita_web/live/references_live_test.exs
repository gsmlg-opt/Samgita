defmodule SamgitaWeb.ReferencesLiveTest do
  use SamgitaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders references page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/references")
    assert html =~ "Reference Documentation"
    assert html =~ "Loki Mode patterns"
  end

  test "shows reference categories", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/references")
    assert html =~ "Architecture"
    assert html =~ "Agents"
  end

  test "renders a reference file", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/references/agents.md")
    assert html =~ "Agent Type Definitions"
  end
end
