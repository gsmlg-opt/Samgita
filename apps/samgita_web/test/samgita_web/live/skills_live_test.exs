defmodule SamgitaWeb.SkillsLiveTest do
  use SamgitaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders skills page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/skills")
    assert html =~ "Claude Skills"
    assert html =~ "skills and extensions"
  end

  test "shows skill entries", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/skills")
    assert html =~ "git-commit"
    assert html =~ "loki-mode"
  end

  test "refresh event reloads skills", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/skills")
    html = render_click(view, "refresh")
    assert html =~ "git-commit"
  end
end
