defmodule SamgitaWeb.SettingsLiveTest do
  use SamgitaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "Settings is the last appbar menu and the theme lives only in Settings", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    menu =
      view
      |> element("nav.appbar-actions")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("a")
      |> Enum.map(&LazyHTML.attribute(&1, "href"))

    assert List.last(menu) == ["/settings"]
    refute has_element?(view, "header.appbar .theme-controller-dropdown")
  end

  test "Settings opens Appearance with the theme switcher", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    assert has_element?(view, "nav.appbar-actions a[href='/settings'][aria-current='page']")
    assert has_element?(view, "#settings-section-appearance[aria-current='page']", "Appearance")
    assert has_element?(view, "#section-appearance #theme-toggle[phx-hook='ThemeSwitcher']")
    # The card would otherwise clip the theme menu that opens below it.
    assert has_element?(view, "#appearance-card.overflow-visible #theme-toggle")
  end

  test "an unknown section falls back to Appearance", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings?section=missing")

    assert has_element?(view, "#settings-section-appearance[aria-current='page']")
    assert has_element?(view, "#section-appearance #theme-toggle")
  end
end
