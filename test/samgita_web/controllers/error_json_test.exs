defmodule SamgitaWeb.ErrorJSONTest do
  use SamgitaWeb.ConnCase, async: true

  test "renders 404" do
    assert SamgitaWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert SamgitaWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end

  test "renders 422" do
    %{errors: %{detail: detail}} = SamgitaWeb.ErrorJSON.render("422.json", %{})
    assert detail in ["Unprocessable Entity", "Unprocessable Content"]
  end

  test "renders 403" do
    assert SamgitaWeb.ErrorJSON.render("403.json", %{}) ==
             %{errors: %{detail: "Forbidden"}}
  end
end
