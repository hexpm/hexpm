defmodule HexpmWeb.PolicyControllerTest do
  use HexpmWeb.ConnCase, async: true

  test "show policy code of conduct" do
    conn =
      build_conn()
      |> get("policies/codeofconduct")

    assert response(conn, 200) =~ "Code of Conduct"
  end

  test "show policy privacy" do
    conn =
      build_conn()
      |> get("policies/privacy")

    assert response(conn, 200) =~ "Privacy Policy"
  end

  test "show policy terms of services" do
    conn =
      build_conn()
      |> get("policies/termsofservice")

    assert response(conn, 200) =~ "Terms of Service"
  end

  test "show policy copyright" do
    conn =
      build_conn()
      |> get("policies/copyright")

    assert response(conn, 200) =~ "Copyright Policy"
  end
end
