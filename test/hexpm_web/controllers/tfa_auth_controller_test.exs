defmodule HexpmWeb.TFAAuthControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    %{user: insert(:user_with_tfa)}
  end

  describe "get /tfa" do
    test "shows auth code form", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", c.user.id)
        |> get("/tfa")

      result = response(conn, 200)
      assert result =~ "Two-factor authentication"
    end

    test "redirects to homepage if tfa_user_id isn't not in the session", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> get("/tfa")

      assert redirected_to(conn) == "/"
    end
  end

  describe "post /tfa" do
    test "with invalid token", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", %{"uid" => c.user.id, "return" => "/"})
        |> post("/tfa", %{"code" => "000000"})

      assert response(conn, 200) =~
               "The verification code you provided is incorrect. Please try again."
    end

    test "with valid token", c do
      token = Hexpm.Accounts.TFA.time_based_token(c.user.tfa.secret)

      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", %{"uid" => c.user.id, "return" => "/"})
        |> post("/tfa", %{"code" => token})

      assert redirected_to(conn) == "/"
    end
  end
end
