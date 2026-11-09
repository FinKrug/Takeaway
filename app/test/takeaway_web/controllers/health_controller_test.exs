defmodule TakeawayWeb.HealthControllerTest do
  use TakeawayWeb.ConnCase

  test "GET /healthz", %{conn: conn} do
    assert text_response(get(conn, ~p"/healthz"), 200) == "ok\n"
  end

  test "GET /readyz", %{conn: conn} do
    assert text_response(get(conn, ~p"/readyz"), 200) == "ok\n"
  end
end
