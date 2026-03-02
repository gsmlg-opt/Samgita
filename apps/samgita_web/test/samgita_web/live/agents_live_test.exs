defmodule SamgitaWeb.AgentsLiveTest do
  use SamgitaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders agent definitions page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/agents")
    assert html =~ "Agent Definitions"
    assert html =~ "37 specialized agents"
  end

  test "shows all swarm categories", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/agents")
    assert html =~ "Engineering Swarm"
    assert html =~ "Operations Swarm"
    assert html =~ "Business Swarm"
    assert html =~ "Review Swarm"
  end

  test "selects a swarm", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/agents")

    html =
      view
      |> element("[phx-click=select_swarm][phx-value-swarm='Engineering Swarm']")
      |> render_click()

    assert html =~ "eng-frontend"
    assert html =~ "eng-backend"
  end

  test "clears swarm selection", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/agents")

    view
    |> element("[phx-click=select_swarm][phx-value-swarm='Engineering Swarm']")
    |> render_click()

    html =
      view
      |> element("[phx-click=clear_selection]")
      |> render_click()

    assert html =~ "Engineering Swarm"
    assert html =~ "Operations Swarm"
  end

  test "toggles agent expansion", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/agents")

    view
    |> element("[phx-click=select_swarm][phx-value-swarm='Engineering Swarm']")
    |> render_click()

    html =
      view
      |> element("[phx-click=toggle_agent][phx-value-agent=eng-frontend]")
      |> render_click()

    assert html =~ "Frontend development"
  end
end
