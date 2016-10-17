defmodule HexWeb.EmailControllerTest do
  use HexWeb.ConnCase, async: true

  setup do
    %{user: create_user("eric", "eric@mail.com", "hunter42")}
  end

  test "verify email with invalid key", c do
    email = hd(c.user.emails)
    conn = get(build_conn(), "email/verify", %{username: c.user.username, email: email.email, key: "invalid"})
    assert response(conn, 400) =~ "We could not verify your email"
    refute conn.assigns.success
  end

  test "verify email with valid key", c do
    email = hd(c.user.emails)
    conn = get(build_conn(), "email/verify", %{username: c.user.username, email: email.email, key: email.verification_key})
    assert response(conn, 200) =~ "Your email has been verified"
    assert conn.assigns.success
  end
end
