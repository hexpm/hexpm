defmodule HexpmWeb.TFARecoveryControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    %{user: insert(:user_with_tfa)}
  end

  describe "get /two_factor_auth/recovery" do
    test "shows auth code form", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", %{"uid" => c.user.id, "return" => "/"})
        |> get("/two_factor_auth/recovery")

      result = response(conn, 200)
      assert result =~ "Enter a recovery code"
    end
  end

  describe "post /two_factor_auth/recovery" do
    test "with invalid code", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", %{"uid" => c.user.id, "return" => "/"})
        |> post("/two_factor_auth/recovery", %{"code" => "0000"})

      assert response(conn, 200) =~
               "The recovery code you provided is incorrect. Please try again."
    end

    test "with valid code", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", %{"uid" => c.user.id, "return" => "/"})
        |> post("/two_factor_auth/recovery", %{"code" => "1234-1234-1234-1234"})

      assert redirected_to(conn) == "/"
    end
  end
end
