defmodule HexpmWeb.TFAAuthControllerTest do
  use HexpmWeb.ConnCase

  setup do
    %{user: insert(:user_with_tfa)}
  end

  describe "get /tfa" do
    test "shows auth code form", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", %{
          "uid" => c.user.id,
          "at" => NaiveDateTime.to_iso8601(NaiveDateTime.utc_now())
        })
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

    test "redirects to homepage if the tfa session is stale", c do
      stale =
        NaiveDateTime.utc_now() |> NaiveDateTime.shift(minute: -16) |> NaiveDateTime.to_iso8601()

      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", %{"uid" => c.user.id, "at" => stale})
        |> get("/tfa")

      assert redirected_to(conn) == "/"
    end
  end

  describe "post /tfa" do
    test "with invalid token", c do
      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", %{
          "uid" => c.user.id,
          "return" => "/",
          "at" => NaiveDateTime.to_iso8601(NaiveDateTime.utc_now())
        })
        |> post("/tfa", %{"code" => "000000"})

      assert response(conn, 200) =~
               "The verification code you provided is incorrect. Please try again."

      user_id = c.user.id

      assert_received {Hexpm.LogLines, :warning,
                       %{method: "tfa", reason: "invalid_code", user_id: ^user_id, path: "/tfa"}}
    end

    test "with valid token", c do
      token = Hexpm.Accounts.TFA.time_based_token(c.user.tfa.secret)

      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", %{
          "uid" => c.user.id,
          "return" => "/",
          "at" => NaiveDateTime.to_iso8601(NaiveDateTime.utc_now())
        })
        |> post("/tfa", %{"code" => token})

      assert redirected_to(conn) == "/"
    end

    # The return value reaches the session from the login form, so the same
    # unsafe spellings rejected in HexpmWeb.LoginControllerTest have to be
    # rejected again here, on the way out of the TFA step.
    for {label, return} <- [
          {"absolute URL", "https%3A%2F%2Fhex.pm%2Foauth%2Fauthorize%3Fclient_id%3Dabc"},
          {"protocol-relative", "//evil.com"},
          {"backslash", "/\\evil.com"},
          {"encoded slash", "/%2fevil.com"},
          {"tab", "/\t/evil.com"},
          {"encoded tab", "/%09/evil.com"},
          {"CRLF", "/\r\n/evil.com"},
          {"null byte", "/dashboard\0"},
          {"delete", "/dashboard\d"}
        ] do
      test "with valid token and #{label} return falls back to user profile", c do
        token = Hexpm.Accounts.TFA.time_based_token(c.user.tfa.secret)

        conn =
          build_conn()
          |> test_login(c.user)
          |> put_session("tfa_user_id", %{
            "uid" => c.user.id,
            "at" => NaiveDateTime.to_iso8601(NaiveDateTime.utc_now()),
            "return" => unquote(return)
          })
          |> post("/tfa", %{"code" => token})

        assert redirected_to(conn) == "/users/#{c.user.username}"
      end
    end

    test "redirects to login after too many failed attempts", c do
      PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage)

      session_data = session_data(c.user)

      # Exhaust rate limit using the throttle function directly (this is the real test)
      Enum.each(1..5, fn _ ->
        HexpmWeb.Plugs.Attack.tfa_user_throttle(c.user.id)
      end)

      # Now make one request - it should be rate limited immediately
      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", session_data)
        |> post("/tfa", %{"code" => "999999"})

      assert redirected_to(conn) == "/login?return=%2F"

      assert Phoenix.Flash.get(conn.assigns.flash, "error") ==
               "Too many incorrect codes. Please log in again."

      assert get_session(conn, "tfa_user_id") == nil
    end

    test "refuses a correct code once the limit is spent", c do
      PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage)

      Enum.each(1..6, fn _ ->
        HexpmWeb.Plugs.Attack.tfa_user_throttle(c.user.id)
      end)

      token = Hexpm.Accounts.TFA.time_based_token(c.user.tfa.secret)

      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", session_data(c.user))
        |> post("/tfa", %{"code" => token})

      assert redirected_to(conn) == "/login?return=%2F"
      assert get_session(conn, "tfa_user_id") == nil
    end

    test "a new login does not hand out a fresh attempt budget", c do
      PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage)

      Enum.each(1..5, fn _ ->
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", session_data(c.user))
        |> post("/tfa", %{"code" => "999999"})
      end)

      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session("tfa_user_id", session_data(c.user))
        |> post("/tfa", %{"code" => "999999"})

      assert redirected_to(conn) == "/login?return=%2F"

      assert Phoenix.Flash.get(conn.assigns.flash, "error") ==
               "Too many incorrect codes. Please log in again."
    end
  end

  defp session_data(user) do
    %{
      "uid" => user.id,
      "return" => "/",
      "at" => NaiveDateTime.to_iso8601(NaiveDateTime.utc_now())
    }
  end
end
