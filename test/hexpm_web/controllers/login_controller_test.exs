defmodule HexpmWeb.LoginControllerTest do
  use HexpmWeb.ConnCase

  setup do
    mock_pwned()
    user = insert(:user)
    %{user: user}
  end

  test "show log in page" do
    conn = get(build_conn(), "/login", %{})
    assert response(conn, 200) =~ "Log in"
  end

  test "ordinary return paths do not change the GitHub login destination" do
    html =
      build_conn()
      |> get("/login", %{return: "/dashboard"})
      |> html_response(200)

    assert html =~ ~s(href="/auth/github")
    refute html =~ ~s(href="/auth/github?return=)
  end

  test "show redirects a signed-in user without a pending SSO link", c do
    conn = build_conn() |> test_login(c.user) |> get("/login")

    assert redirected_to(conn) == "/users/#{c.user.username}"
  end

  test "log in with correct password", c do
    conn = post(build_conn(), "/login", %{username: c.user.username, password: "password"})
    assert redirected_to(conn) == "/users/#{c.user.username}"

    assert get_session(conn, "session_token")
    refute get_session(conn, "user_id")
  end

  @tag :focus
  test "log in when tfa enabled" do
    user = insert(:user_with_tfa)
    conn = post(build_conn(), "/login", %{username: user.username, password: "password"})
    assert redirected_to(conn) == "/tfa"

    tfa_data = get_session(conn, "tfa_user_id")
    assert tfa_data["uid"] == user.id
    assert tfa_data["return"] == nil
    refute tfa_data["session_token"]
    refute get_session(conn, "session_token")
    refute Repo.exists?(from(session in Hexpm.UserSession, where: session.user_id == ^user.id))
  end

  test "log in keeps you logged in", c do
    conn = post(build_conn(), "/login", %{username: c.user.username, password: "password"})
    assert redirected_to(conn) == "/users/#{c.user.username}"

    conn = conn |> recycle() |> get("/")
    assert get_session(conn, "session_token")
  end

  # Browsers strip tab, LF and CR while parsing a URL, so a return path like
  # "/<TAB>/evil.com" passes a naive "does it start with a single slash" check
  # but resolves as the scheme-relative "//evil.com" (CVE-2026-64941).
  for {label, return} <- [
        {"absolute URL", "https://evil.com"},
        {"absolute http URL", "http://evil.com/dashboard"},
        {"javascript scheme", "javascript:alert(1)"},
        {"data scheme", "data:text/html,x"},
        {"protocol-relative", "//evil.com"},
        {"protocol-relative with path", "//evil.com/dashboard"},
        {"backslash", "/\\evil.com"},
        {"encoded slash", "/%2fevil.com"},
        {"encoded backslash", "/%5cevil.com"},
        {"bare host", "evil.com"},
        {"tab", "/\t/evil.com"},
        {"encoded tab", "/%09/evil.com"},
        {"line feed", "/\n/evil.com"},
        {"carriage return", "/\r/evil.com"},
        {"CRLF", "/\r\n/evil.com"},
        {"header injection", "/dashboard\r\nSet-Cookie: x=1"},
        {"null byte", "/dashboard\0"},
        {"vertical tab", "/dashboard\v"},
        {"form feed", "/dashboard\f"},
        {"delete", "/dashboard\d"}
      ] do
    test "log in refuses to redirect off-site via a #{label} return path", c do
      conn =
        post(build_conn(), "/login", %{
          username: c.user.username,
          password: "password",
          return: unquote(return)
        })

      assert redirected_to(conn) == "/users/#{c.user.username}"
    end
  end

  for return <- ["/", "/dashboard", "/packages?search=ecto"] do
    test "log in honours the on-site return path #{inspect(return)}", c do
      conn =
        post(build_conn(), "/login", %{
          username: c.user.username,
          password: "password",
          return: unquote(return)
        })

      assert redirected_to(conn) == unquote(return)
    end
  end

  test "log in with wrong password", c do
    PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage)

    conn = post(build_conn(), "/login", %{username: c.user.username, password: "WRONG"})
    assert response(conn, 400) =~ "Log in"

    assert Phoenix.Flash.get(conn.assigns.flash, "error") ==
             "Invalid username, email or password."

    refute get_session(conn, "session_token")
  end

  test "log in with unconfirmed email", c do
    PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage)

    Ecto.Changeset.change(hd(c.user.emails), verified: false) |> Hexpm.Repo.update!()

    conn = post(build_conn(), "/login", %{username: c.user.username, password: "password"})
    assert response(conn, 400) =~ "Log in"
    assert Phoenix.Flash.get(conn.assigns.flash, "error") =~ "Email has not been verified yet."
    refute get_session(conn, "session_token")
  end

  test "log out", c do
    conn =
      build_conn()
      |> test_login(c.user)
      |> put_session("tfa_setup_secret", "secret")
      |> post("/logout")

    assert redirected_to(conn) == "/"
    refute get_session(conn, "session_token")
    refute get_session(conn, "tfa_setup_secret")
  end

  test "deactivated", c do
    Ecto.Changeset.change(c.user, deactivated_at: DateTime.utc_now()) |> Repo.update!()
    conn = post(build_conn(), "/login", %{username: c.user.username, password: "password"})
    assert redirected_to(conn) == "/users/#{c.user.username}"
    conn = get(conn, "/")
    assert response(conn, 400)
  end

  test "rate limits failed login attempts from same IP", c do
    PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage)

    # Exhaust IP limit (10 attempts)
    Enum.each(1..10, fn _ ->
      conn = post(build_conn(), "/login", %{username: c.user.username, password: "WRONG"})
      assert response(conn, 400)

      assert Phoenix.Flash.get(conn.assigns.flash, "error") ==
               "Invalid username, email or password."
    end)

    # 11th attempt should trigger IP rate limiting
    conn = post(build_conn(), "/login", %{username: c.user.username, password: "WRONG"})
    assert response(conn, 429)

    assert Phoenix.Flash.get(conn.assigns.flash, "error") ==
             "Too many login attempts from your IP. Please try again later."
  end
end
