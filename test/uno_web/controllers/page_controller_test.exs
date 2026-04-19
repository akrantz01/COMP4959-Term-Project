defmodule UnoWeb.PageControllerTest do
  use UnoWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "UNO"
    assert html =~ "Create New Room"
    assert html =~ "Join Room"
  end
end
