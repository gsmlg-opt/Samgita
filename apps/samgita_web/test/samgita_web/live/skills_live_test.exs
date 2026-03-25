defmodule SamgitaWeb.SkillsLiveTest do
  use SamgitaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders skills page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/skills")
    assert html =~ "Claude Skills"
    assert html =~ "skills and extensions"
  end

  test "shows agent type entries from Types module", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/skills")
    # Skills now come from Samgita.Agent.Types.all()
    assert html =~ "eng-backend"
    assert html =~ "eng-frontend"
    assert html =~ "Engineering"
  end

  test "refresh event reloads skills", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/skills")
    html = render_click(view, "refresh")
    assert html =~ "eng-backend"
  end
end
