defmodule ConcertMatchWeb.HealthControllerTest do
  use ConcertMatchWeb.ConnCase, async: true

  test "reports ok when the database answers", %{conn: conn} do
    conn = get(conn, ~p"/healthz")

    assert response(conn, 200) == "ok"
  end

  test "needs no session or login", %{conn: conn} do
    # Render polls this on every health check; requiring a session would mean
    # issuing a cookie per poll, and requiring a login would fail it outright.
    conn = get(conn, ~p"/healthz")

    assert conn.status == 200
    assert conn.resp_cookies == %{}
  end
end
