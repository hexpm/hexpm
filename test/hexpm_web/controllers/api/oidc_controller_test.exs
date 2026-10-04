defmodule HexpmWeb.API.OIDCControllerTest do
  use HexpmWeb.ConnCase, async: false

  test "GET /api/oidc/audience" do
    conn = get(build_conn(), "/api/oidc/audience")
    assert json_response(conn, 200) == %{"audience" => "hexpm"}
  end

  test "GET /api/oidc/audience returns 404 when feature disabled" do
    previous = Application.get_env(:hexpm, :features)
    Application.put_env(:hexpm, :features, trusted_publishers: false)
    on_exit(fn -> Application.put_env(:hexpm, :features, previous) end)

    body =
      build_conn()
      |> get("/api/oidc/audience")
      |> json_response(404)

    assert body["error"] == "not_found"
  end
end
