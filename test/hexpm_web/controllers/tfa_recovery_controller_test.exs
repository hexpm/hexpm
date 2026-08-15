defmodule HexpmWeb.TFARecoveryControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    %{user: insert(:user_with_tfa)}
  end

  describe "get /tfa/recovery" do
    test "shows auth code form", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", %{
          "uid" => c.user.id,
          "return" => "/",
          "at" => NaiveDateTime.to_iso8601(NaiveDateTime.utc_now())
        })
        |> get("/tfa/recovery")

      result = response(conn, 200)
      assert result =~ "Recovery code"
    end

    test "redirects to homepage if the tfa session is stale", c do
      stale =
        NaiveDateTime.utc_now() |> NaiveDateTime.shift(minute: -16) |> NaiveDateTime.to_iso8601()

      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", %{"uid" => c.user.id, "at" => stale})
        |> get("/tfa/recovery")

      assert redirected_to(conn) == "/"
    end
  end

  describe "post /tfa/recovery" do
    test "with invalid code", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", %{
          "uid" => c.user.id,
          "return" => "/",
          "at" => NaiveDateTime.to_iso8601(NaiveDateTime.utc_now())
        })
        |> post("/tfa/recovery", %{"code" => "0000"})

      assert response(conn, 200) =~
               "The recovery code you provided is incorrect. Please try again."
    end

    test "with valid code", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", %{
          "uid" => c.user.id,
          "return" => "/",
          "at" => NaiveDateTime.to_iso8601(NaiveDateTime.utc_now())
        })
        |> post("/tfa/recovery", %{"code" => "1234-1234-1234-1234"})

      assert redirected_to(conn) == "/"
    end

    test "with valid code and non-path return falls back to user profile", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", %{
          "uid" => c.user.id,
          "return" => "https://example.com",
          "at" => NaiveDateTime.to_iso8601(NaiveDateTime.utc_now())
        })
        |> post("/tfa/recovery", %{"code" => "1234-1234-1234-1234"})

      assert redirected_to(conn) == "/users/#{c.user.username}"
    end

    test "with valid code and protocol-relative return falls back to user profile", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", %{
          "uid" => c.user.id,
          "return" => "//example.com",
          "at" => NaiveDateTime.to_iso8601(NaiveDateTime.utc_now())
        })
        |> post("/tfa/recovery", %{"code" => "1234-1234-1234-1234"})

      assert redirected_to(conn) == "/users/#{c.user.username}"
    end
  end
end
