defmodule ConcertMatchWeb.ErrorJSONTest do
  use ConcertMatchWeb.ConnCase, async: true

  test "renders 404" do
    assert ConcertMatchWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert ConcertMatchWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
