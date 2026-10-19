defmodule HexpmWeb.API.OIDCControllerTest do
  use HexpmWeb.ConnCase, async: false

  test "GET /api/oidc/audience" do
    conn = get(build_conn(), "/api/oidc/audience")
    assert json_response(conn, 200) == %{"audience" => "hexpm"}
  end

  test "GET /api/oidc/audience ignores a refused token in the Authorization header" do
    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer invalid.jwt.token")
      |> get("/api/oidc/audience")

    assert json_response(conn, 200) == %{"audience" => "hexpm"}
  end

  test "GET /api/oidc/audience returns 404 when feature disabled" do
    put_feature_flag(:workload_identity, mode: :off)

    body =
      build_conn()
      |> get("/api/oidc/audience")
      |> json_response(404)

    assert body["error"] == "not_found"
  end
end
