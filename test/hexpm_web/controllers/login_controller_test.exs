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

  test "log in with correct password", c do
    conn = post(build_conn(), "/login", %{username: c.user.username, password: "password"})
    assert redirected_to(conn) == "/users/#{c.user.username}"

    assert get_session(conn, "session_token")
    refute last_session().data["user_id"]
  end

  @tag :focus
  test "log in when tfa enabled" do
    user = insert(:user_with_tfa)
    conn = post(build_conn(), "/login", %{username: user.username, password: "password"})
    assert redirected_to(conn) == "/tfa"

    tfa_data = get_session(conn, "tfa_user_id")
    assert tfa_data["uid"] == user.id
    assert tfa_data["return"] == nil
    assert tfa_data["session_token"]
  end

  test "log in keeps you logged in", c do
    conn = post(build_conn(), "/login", %{username: c.user.username, password: "password"})
    assert redirected_to(conn) == "/users/#{c.user.username}"

    conn = conn |> recycle() |> get("/")
    assert get_session(conn, "session_token")
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
