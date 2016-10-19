defmodule HexWeb.DashboardControllerTest do
  use HexWeb.ConnCase, async: true

  alias HexWeb.Users

  setup do
    %{user: create_user("eric", "eric@mail.com", "hunter42"), password: "hunter42"}
  end

  test "show profile", c do
    conn = build_conn()
           |> test_login(c.user)
           |> get("dashboard/profile")

    assert response(conn, 200) =~ "Public profile"
  end

  test "update profile", c do
    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/profile", %{user: %{full_name: "New Name"}})

    assert redirected_to(conn) == "/dashboard/profile"
    assert get_flash(conn, :info) =~ "Profile updated successfully"
    assert Users.get(c.user.username).full_name == "New Name"
  end

  test "show password", c do
    conn = build_conn()
           |> test_login(c.user)
           |> get("dashboard/password")

    assert response(conn, 200) =~ "Change password"
  end

  test "update password", c do
    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/password", %{user: %{password_current: c.password, password: "newpass", password_confirmation: "newpass"}})

    assert redirected_to(conn) == "/dashboard/password"
    assert get_flash(conn, :info) =~ "Your password has been updated"
    assert {:ok, _} = HexWeb.Auth.password_auth(c.user.username, "newpass")
    assert :error = HexWeb.Auth.password_auth(c.user.username, c.password)
  end

  test "update password invalid current password", c do
    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/password", %{user: %{password_current: "WRONG", password: "newpass", password_confirmation: "newpass"}})

    assert response(conn, 400) =~ "Change password"
    assert {:ok, _} = HexWeb.Auth.password_auth(c.user.username, c.password)
  end

  test "update password invalid confirmation password", c do
    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/password", %{user: %{password_current: c.password, password: "newpass", password_confirmation: "WRONG"}})

    assert response(conn, 400) =~ "Change password"
    assert {:ok, _} = HexWeb.Auth.password_auth(c.user.username, c.password)
    assert :error = HexWeb.Auth.password_auth(c.user.username, "newpass")
  end

  test "update password missing current password", c do
    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/password", %{user: %{password: "newpass", password_confirmation: "newpass"}})

    assert response(conn, 400) =~ "Change password"
    assert {:ok, _} = HexWeb.Auth.password_auth(c.user.username, c.password)
    assert :error = HexWeb.Auth.password_auth(c.user.username, "newpass")
  end

  test "add email", c do
    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/email", %{email: %{email: "new@mail.com"}})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :info) =~ "A verification email has been sent"
    user = HexWeb.Repo.get!(HexWeb.User, c.user.id) |> HexWeb.Repo.preload(:emails)
    email = Enum.find(user.emails, &(&1.email == "new@mail.com"))
    refute email.verified
    refute email.primary
    refute email.public
  end

  test "cannot add existing email", c do
    email = hd(c.user.emails).email

    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/email", %{email: %{email: email}})

    response(conn, 400)
    assert conn.resp_body =~ "Add email"
    assert conn.resp_body =~ "has already been taken"
  end

  test "remove email", c do
    {:ok, _} = Users.add_email(c.user, %{email: "new@mail.com"})

    conn = build_conn()
           |> test_login(c.user)
           |> delete("dashboard/email", %{email: "new@mail.com"})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :info) =~ "Removed email"
    user = HexWeb.Repo.get!(HexWeb.User, c.user.id) |> HexWeb.Repo.preload(:emails)
    refute Enum.find(user.emails, &(&1.email == "new@mail.com"))
  end

  test "cannot remove primary email", c do
    conn = build_conn()
           |> test_login(c.user)
           |> delete("dashboard/email", %{email: "eric@mail.com"})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :error) =~ "Cannot remove primary email"
    user = HexWeb.Repo.get!(HexWeb.User, c.user.id) |> HexWeb.Repo.preload(:emails)
    assert Enum.find(user.emails, &(&1.email == "eric@mail.com"))
  end

  test "make email primary", c do
    {:ok, user} = Users.add_email(c.user, %{email: "new@mail.com"})
    email = Enum.find(user.emails, &(&1.email == "new@mail.com"))
    Ecto.Changeset.change(email, %{verified: true}) |> HexWeb.Repo.update!

    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/email/primary", %{email: "new@mail.com"})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :info) =~ "primary email was changed"

    user = HexWeb.Repo.get!(HexWeb.User, c.user.id) |> HexWeb.Repo.preload(:emails)
    assert Enum.find(user.emails, &(&1.email == "new@mail.com")).primary
    refute Enum.find(user.emails, &(&1.email == "eric@mail.com")).primary
  end

  test "cannot make unverified email primary", c do
    {:ok, _} = Users.add_email(c.user, %{email: "new@mail.com"})

    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/email/primary", %{email: "new@mail.com"})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :error) =~ "not verified"

    user = HexWeb.Repo.get!(HexWeb.User, c.user.id) |> HexWeb.Repo.preload(:emails)
    refute Enum.find(user.emails, &(&1.email == "new@mail.com")).primary
  end

  test "make email public", c do
    {:ok, user} = Users.add_email(c.user, %{email: "new@mail.com"})
    email = Enum.find(user.emails, &(&1.email == "new@mail.com"))
    Ecto.Changeset.change(email, %{verified: true}) |> HexWeb.Repo.update!

    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/email/public", %{email: "new@mail.com"})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :info) =~ "public email was changed"

    user = HexWeb.Repo.get!(HexWeb.User, c.user.id) |> HexWeb.Repo.preload(:emails)
    assert Enum.find(user.emails, &(&1.email == "new@mail.com")).public
    refute Enum.find(user.emails, &(&1.email == "eric@mail.com")).public
  end

  test "resend verify email", c do
    {:ok, _} = Users.add_email(c.user, %{email: "new@mail.com"})

    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/email/resend", %{email: "new@mail.com"})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :info) =~ "verification email has been sent"

    {subject, contents} = HexWeb.Mail.Local.read("new@mail.com")
    assert subject =~ "Hex.pm"
    assert contents =~ "email/verify?username=#{c.user.username}"
  end
end
