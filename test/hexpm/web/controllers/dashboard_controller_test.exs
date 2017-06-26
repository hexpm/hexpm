defmodule Hexpm.Web.DashboardControllerTest do
  # TODO: debug Bamboo.Test race conditions and change back to async: true
  use Hexpm.ConnCase, async: false

  alias Hexpm.Accounts.Auth
  alias Hexpm.Accounts.User
  alias Hexpm.Accounts.Users

  defp add_email(user, email) do
    {:ok, user} = Users.add_email(user, %{email: email}, audit: {user, "TEST"})
    user
  end

  setup do
    %{user: create_user("eric", "eric@mail.com", "hunter42"), password: "hunter42"}
  end

  test "show index page", context do
      conn = build_conn()
             |> test_login(context.user)
             |> get("dashboard")
      assert redirected_to(conn) == "/dashboard/profile"
  end

  test "show profile", c do
    conn = build_conn()
           |> test_login(c.user)
           |> get("dashboard/profile")

    assert response(conn, 200) =~ "Public profile"
  end

  test "requires login" do
    conn = get(build_conn(), "dashboard/profile")
    assert redirected_to(conn) == "/login?return=dashboard%2Fprofile"
  end

  test "update profile", c do
    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/profile", %{user: %{full_name: "New Name"}})

    assert redirected_to(conn) == "/dashboard/profile"
    assert get_flash(conn, :info) =~ "Profile updated successfully"
    assert Users.get(c.user.username).full_name == "New Name"
  end

  test "update profile change public email", c do
    user = add_email(c.user, "new@mail.com")
    email = Enum.find(user.emails, &(&1.email == "new@mail.com"))
    Ecto.Changeset.change(email, %{verified: true}) |> Hexpm.Repo.update!
    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/profile", %{user: %{public_email: "new@mail.com"}})

    assert redirected_to(conn) == "/dashboard/profile"
    assert get_flash(conn, :info) =~ "Profile updated successfully"

    user = Hexpm.Repo.get!(Hexpm.Accounts.User, c.user.id) |> Hexpm.Repo.preload(:emails)
    assert Enum.find(user.emails, &(&1.email == "new@mail.com")).public
    refute Enum.find(user.emails, &(&1.email == "eric@mail.com")).public
  end

  test "update profile don't show public email", c do
    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/profile", %{user: %{public_email: "none"}})

    assert redirected_to(conn) == "/dashboard/profile"
    assert get_flash(conn, :info) =~ "Profile updated successfully"
    refute Users.get(c.user.username) |> Users.with_emails |> User.email(:public)
  end

  test "update profile with no emails", c do
    Hexpm.Repo.delete_all(Hexpm.Accounts.Email)

    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/profile", %{user: %{public_email: "none"}})

    assert redirected_to(conn) == "/dashboard/profile"
    assert get_flash(conn, :info) =~ "Profile updated successfully"
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
    assert {:ok, _} = Auth.password_auth(c.user.username, "newpass")
    assert :error = Auth.password_auth(c.user.username, c.password)
  end

  test "update password invalid current password", c do
    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/password", %{user: %{password_current: "WRONG", password: "newpass", password_confirmation: "newpass"}})

    assert response(conn, 400) =~ "Change password"
    assert {:ok, _} = Auth.password_auth(c.user.username, c.password)
  end

  test "update password invalid confirmation password", c do
    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/password", %{user: %{password_current: c.password, password: "newpass", password_confirmation: "WRONG"}})

    assert response(conn, 400) =~ "Change password"
    assert {:ok, _} = Auth.password_auth(c.user.username, c.password)
    assert :error = Auth.password_auth(c.user.username, "newpass")
  end

  test "update password missing current password", c do
    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/password", %{user: %{password: "newpass", password_confirmation: "newpass"}})

    assert response(conn, 400) =~ "Change password"
    assert {:ok, _} = Auth.password_auth(c.user.username, c.password)
    assert :error = Auth.password_auth(c.user.username, "newpass")
  end

  test "add email", c do
    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/email", %{email: %{email: "new@mail.com"}})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :info) =~ "A verification email has been sent"
    user = Hexpm.Repo.get!(Hexpm.Accounts.User, c.user.id) |> Hexpm.Repo.preload(:emails)
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
    assert conn.resp_body =~ "email already in use"
  end

  test "can add existing email which is not verified", c do
    u2 = %{user: create_user("techgaun", "techgaun@example.com", "hunter24", false), password: "hunter24"}
    email = hd(u2.user.emails).email

    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/email", %{email: %{email: email}})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :info) =~ "A verification email has been sent"
  end

  test "verified email logs appropriate user correctly", c do
    u2 = %{user: create_user("techgaun", "techgaun@example.com", "hunter24", false), password: "hunter24"}
    user = add_email(c.user, hd(u2.user.emails).email)
    [dup_email] = tl(user.emails)

    conn = build_conn()
      |> get("email/verify", %{username: c.user.username, email: dup_email.email, key: dup_email.verification_key})

    assert redirected_to(conn) == "/"
    assert get_flash(conn, :info) =~ "has been verified"

    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/email/primary", %{email: dup_email.email})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :info) =~ "primary email was changed"

    conn = post(build_conn(), "login", %{username: dup_email.email, password: c.password})
    assert redirected_to(conn) == "/users/#{c.user.username}"
    assert get_session(conn, "user_id") == c.user.id

    conn = build_conn()
      |> get("email/verify", %{username: u2.user.username, email: dup_email.email, key: hd(u2.user.emails).verification_key})

    assert redirected_to(conn) == "/"
    assert get_flash(conn, :error) =~ "failed to verify."
  end

  test "remove email", c do
    add_email(c.user, "new@mail.com")

    conn = build_conn()
           |> test_login(c.user)
           |> delete("dashboard/email", %{email: "new@mail.com"})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :info) =~ "Removed email"
    user = Hexpm.Repo.get!(Hexpm.Accounts.User, c.user.id) |> Hexpm.Repo.preload(:emails)
    refute Enum.find(user.emails, &(&1.email == "new@mail.com"))
  end

  test "cannot remove primary email", c do
    conn = build_conn()
           |> test_login(c.user)
           |> delete("dashboard/email", %{email: "eric@mail.com"})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :error) =~ "Cannot remove primary email"
    user = Hexpm.Repo.get!(Hexpm.Accounts.User, c.user.id) |> Hexpm.Repo.preload(:emails)
    assert Enum.find(user.emails, &(&1.email == "eric@mail.com"))
  end

  test "make email primary", c do
    user = add_email(c.user, "new@mail.com")
    email = Enum.find(user.emails, &(&1.email == "new@mail.com"))
    Ecto.Changeset.change(email, %{verified: true}) |> Hexpm.Repo.update!

    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/email/primary", %{email: "new@mail.com"})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :info) =~ "primary email was changed"

    user = Hexpm.Repo.get!(Hexpm.Accounts.User, c.user.id) |> Hexpm.Repo.preload(:emails)
    assert Enum.find(user.emails, &(&1.email == "new@mail.com")).primary
    refute Enum.find(user.emails, &(&1.email == "eric@mail.com")).primary
  end

  test "cannot make unverified email primary", c do
    add_email(c.user, "new@mail.com")

    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/email/primary", %{email: "new@mail.com"})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :error) =~ "not verified"

    user = Hexpm.Repo.get!(Hexpm.Accounts.User, c.user.id) |> Hexpm.Repo.preload(:emails)
    refute Enum.find(user.emails, &(&1.email == "new@mail.com")).primary
  end

  test "make email public", c do
    user = add_email(c.user, "new@mail.com")
    email = Enum.find(user.emails, &(&1.email == "new@mail.com"))
    Ecto.Changeset.change(email, %{verified: true}) |> Hexpm.Repo.update!

    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/email/public", %{email: "new@mail.com"})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :info) =~ "public email was changed"

    user = Hexpm.Repo.get!(Hexpm.Accounts.User, c.user.id) |> Hexpm.Repo.preload(:emails)
    assert Enum.find(user.emails, &(&1.email == "new@mail.com")).public
    refute Enum.find(user.emails, &(&1.email == "eric@mail.com")).public
  end

  test "resend verify email", c do
    add_email(c.user, "new@mail.com")

    conn = build_conn()
           |> test_login(c.user)
           |> post("dashboard/email/resend", %{email: "new@mail.com"})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :info) =~ "verification email has been sent"

    [email_one, email_two] = Bamboo.SentEmail.all
    assert email_one.subject =~ "Hex.pm"
    assert email_one.html_body =~ "email/verify?username=#{c.user.username}"

    assert email_two.subject =~ "Hex.pm"
    assert email_two.html_body =~ "email/verify?username=#{c.user.username}"
  end
end
