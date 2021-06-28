defmodule HexpmWeb.Dashboard.EmailControllerTest do
  use HexpmWeb.ConnCase, async: true
  use Bamboo.Test

  alias Hexpm.Accounts.Users

  defp add_email(user, email) do
    {:ok, user} = Users.add_email(user, %{email: email}, audit: audit_data(user))
    user
  end

  setup do
    email = Fake.sequence(:email)
    mock_pwned()

    %{
      user: insert(:user, emails: [build(:email, email: email)]),
      email: email
    }
  end

  test "show emails", c do
    conn =
      build_conn()
      |> test_login(c.user)
      |> get("dashboard/email")

    assert response(conn, 200) =~ "Emails"
  end

  test "requires login" do
    conn = get(build_conn(), "dashboard/email")
    assert redirected_to(conn) == "/login?return=dashboard%2Femail"
  end

  test "add email", c do
    email = Fake.sequence(:email)

    conn =
      build_conn()
      |> test_login(c.user)
      |> post("dashboard/email", %{email: %{email: email}})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :info) =~ "A verification email has been sent"
    user = Hexpm.Repo.get!(Hexpm.Accounts.User, c.user.id) |> Hexpm.Repo.preload(:emails)
    email = Enum.find(user.emails, &(&1.email == email))
    refute email.verified
    refute email.primary
    refute email.public
  end

  test "cannot add existing email", c do
    email = hd(c.user.emails).email

    conn =
      build_conn()
      |> test_login(c.user)
      |> post("dashboard/email", %{email: %{email: email}})

    response(conn, 400)
    assert conn.resp_body =~ "Add email"
    assert conn.resp_body =~ "already in use"
  end

  test "can add existing email which is not verified", c do
    user2 = insert(:user, emails: [build(:email, verified: false)])
    email = hd(user2.emails).email

    conn =
      build_conn()
      |> test_login(c.user)
      |> post("dashboard/email", %{email: %{email: email}})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :info) =~ "A verification email has been sent"
  end

  test "verified email logs appropriate user correctly", c do
    user2 = insert(:user, emails: [build(:email, verified: false)])
    user = add_email(c.user, hd(user2.emails).email)
    [dup_email] = tl(user.emails)

    conn =
      build_conn()
      |> get("email/verify", %{
        username: c.user.username,
        email: dup_email.email,
        key: dup_email.verification_key
      })

    assert redirected_to(conn) == "/"
    assert get_flash(conn, :info) =~ "has been verified"

    conn =
      build_conn()
      |> test_login(c.user)
      |> post("dashboard/email/primary", %{email: dup_email.email})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :info) =~ "primary email was changed"

    conn = post(build_conn(), "login", %{username: dup_email.email, password: "password"})
    assert redirected_to(conn) == "/users/#{c.user.username}"
    assert get_session(conn, "user_id") == c.user.id

    conn =
      build_conn()
      |> get("email/verify", %{
        username: user2.username,
        email: dup_email.email,
        key: hd(user2.emails).verification_key
      })

    assert redirected_to(conn) == "/"
    assert get_flash(conn, :error) =~ "failed to verify."
  end

  test "remove email", c do
    email = Fake.sequence(:email)
    add_email(c.user, email)

    conn =
      build_conn()
      |> test_login(c.user)
      |> delete("dashboard/email", %{email: email})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :info) =~ "Removed email"
    user = Hexpm.Repo.get!(Hexpm.Accounts.User, c.user.id) |> Hexpm.Repo.preload(:emails)
    refute Enum.find(user.emails, &(&1.email == email))
  end

  test "cannot remove primary email", c do
    conn =
      build_conn()
      |> test_login(c.user)
      |> delete("dashboard/email", %{email: c.email})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :error) =~ "Cannot remove primary email"
    user = Hexpm.Repo.get!(Hexpm.Accounts.User, c.user.id) |> Hexpm.Repo.preload(:emails)
    assert Enum.find(user.emails, &(&1.email == c.email))
  end

  test "make email primary", c do
    new_email = Fake.sequence(:email)
    user = add_email(c.user, new_email)
    email = Enum.find(user.emails, &(&1.email == new_email))
    Ecto.Changeset.change(email, %{verified: true}) |> Hexpm.Repo.update!()

    conn =
      build_conn()
      |> test_login(c.user)
      |> post("dashboard/email/primary", %{email: new_email})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :info) =~ "primary email was changed"

    user = Hexpm.Repo.get!(Hexpm.Accounts.User, c.user.id) |> Hexpm.Repo.preload(:emails)
    assert Enum.find(user.emails, &(&1.email == new_email)).primary
    refute Enum.find(user.emails, &(&1.email == c.email)).primary
  end

  test "cannot make unverified email primary", c do
    email = Fake.sequence(:email)
    add_email(c.user, email)

    conn =
      build_conn()
      |> test_login(c.user)
      |> post("dashboard/email/primary", %{email: email})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :error) =~ "not verified"

    user = Hexpm.Repo.get!(Hexpm.Accounts.User, c.user.id) |> Hexpm.Repo.preload(:emails)
    refute Enum.find(user.emails, &(&1.email == email)).primary
  end

  test "make email public", c do
    new_email = Fake.sequence(:email)
    user = add_email(c.user, new_email)
    email = Enum.find(user.emails, &(&1.email == new_email))
    Ecto.Changeset.change(email, %{verified: true}) |> Hexpm.Repo.update!()

    conn =
      build_conn()
      |> test_login(c.user)
      |> post("dashboard/email/public", %{email: new_email})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :info) =~ "public email was changed"

    user = Hexpm.Repo.get!(Hexpm.Accounts.User, c.user.id) |> Hexpm.Repo.preload(:emails)
    assert Enum.find(user.emails, &(&1.email == new_email)).public
    refute Enum.find(user.emails, &(&1.email == c.email)).public
  end

  test "make email private", c do
    user_email = Enum.find(c.user.emails, & &1.public)

    conn =
      build_conn()
      |> test_login(c.user)
      |> post("dashboard/email/public", %{email: "none"})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :info) =~ "Your public email was changed to none."

    user = Hexpm.Repo.get!(Hexpm.Accounts.User, c.user.id) |> Hexpm.Repo.preload(:emails)
    refute Enum.find(user.emails, &(&1.email == user_email.email)).public
  end

  test "set email for gravatar", c do
    new_email = Fake.sequence(:email)
    user = add_email(c.user, new_email)
    email = Enum.find(user.emails, &(&1.email == new_email))
    Ecto.Changeset.change(email, %{verified: true}) |> Hexpm.Repo.update!()

    conn =
      build_conn()
      |> test_login(c.user)
      |> post("dashboard/email/gravatar", %{email: new_email})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :info) =~ "gravatar email was changed"

    user = Hexpm.Repo.get!(Hexpm.Accounts.User, c.user.id) |> Hexpm.Repo.preload(:emails)
    assert Enum.find(user.emails, &(&1.email == new_email)).gravatar
    refute Enum.find(user.emails, &(&1.email == c.email)).gravatar
  end

  test "unknown email cannot be gravatar email", c do
    unknown_email = Fake.sequence(:email)
    email = Enum.find(c.user.emails, &(&1.email == c.email))
    Hexpm.Accounts.Email.toggle_flag(email, :gravatar, true) |> Hexpm.Repo.update!()

    conn =
      build_conn()
      |> test_login(c.user)
      |> post("dashboard/email/gravatar", %{email: unknown_email})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :error) =~ "Unknown email"

    user = Hexpm.Repo.get!(Hexpm.Accounts.User, c.user.id) |> Hexpm.Repo.preload(:emails)
    assert Enum.find(user.emails, &(&1.email == c.email)).gravatar
    refute Enum.find(user.emails, &(&1.email == unknown_email))
  end

  test "unverified email cannot be gravatar email", c do
    unverified_email = Fake.sequence(:email)
    add_email(c.user, unverified_email)

    conn =
      build_conn()
      |> test_login(c.user)
      |> post("dashboard/email/gravatar", %{email: unverified_email})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :error) =~ "not verified"

    user = Hexpm.Repo.get!(Hexpm.Accounts.User, c.user.id) |> Hexpm.Repo.preload(:emails)
    refute Enum.find(user.emails, &(&1.email == unverified_email)).gravatar
  end

  test "resend verify email", c do
    new_email = Fake.sequence(:email)
    user = add_email(c.user, new_email)

    conn =
      build_conn()
      |> test_login(user)
      |> post("dashboard/email/resend", %{email: new_email})

    assert redirected_to(conn) == "/dashboard/email"
    assert get_flash(conn, :info) =~ "verification email has been sent"

    assert_delivered_email(Hexpm.Emails.verification(user, List.last(user.emails)))
    assert_delivered_email(Hexpm.Emails.verification(user, List.last(user.emails)))
  end
end
