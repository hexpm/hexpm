defmodule HexWeb.EmailControllerTest do
  use HexWeb.ConnCase, async: true

  setup do
    %{user: create_user("eric", "eric@mail.com", "hunter42")}
  end

  test "verify email with invalid key", c do
    email = hd(c.user.emails)
    conn = get(build_conn(), "email/verify", %{username: c.user.username, email: email.email, key: "invalid"})

    assert redirected_to(conn) == "/"
    assert get_flash(conn, :error) =~ "failed to verify"
  end

  test "verify email with invalid username" do
    conn = get(build_conn(), "email/verify", %{username: "invalid", email: "invalid", key: "invalid"})

    assert redirected_to(conn) == "/"
    assert get_flash(conn, :error) =~ "failed to verify"
  end

  test "verify email with valid key", c do
    email = hd(c.user.emails)
    conn = get(build_conn(), "email/verify", %{username: c.user.username, email: email.email, key: email.verification_key})

    assert redirected_to(conn) == "/"
    assert get_flash(conn, :info) =~ "has been verified"
  end
end
