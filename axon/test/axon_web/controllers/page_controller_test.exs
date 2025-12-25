defmodule AxonWeb.PageControllerTest do
  use AxonWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert conn.status in [301, 302, 307, 308]
    assert get_resp_header(conn, "location") == ["/setup"]
  end
end
