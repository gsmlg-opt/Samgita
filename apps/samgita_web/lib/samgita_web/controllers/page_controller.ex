defmodule SamgitaWeb.PageController do
  use SamgitaWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
