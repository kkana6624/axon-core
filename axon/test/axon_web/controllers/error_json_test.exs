defmodule AxonWeb.ErrorJSONTest do
  use AxonWeb.ConnCase, async: true

  test "renders 404" do
    assert AxonWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert AxonWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
