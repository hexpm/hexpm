defmodule HexpmWeb.EmailVerificationControllerTest do
  use HexpmWeb.ConnCase, async: true
  use Bamboo.Test
  alias Hexpm.Accounts.{User, Users}

  describe "GET /email/verify" do
    setup do
      email =
        build(
          :email,
          verified: false,
          verification_key: Hexpm.Accounts.Auth.gen_key(),
          verification_expiry: DateTime.utc_now()
        )

      user = insert(:user, emails: [email])
      %{user: user}
    end

    test "verify email with invalid key", c do
      email = hd(c.user.emails)

      conn =
        get(build_conn(), "email/verify", %{
          username: c.user.username,
          email: email.email,
          key: "invalid"
        })

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :error) =~ "failed to verify"

      user = Users.get(c.user.username, [:emails])
      refute hd(user.emails).verified
    end

    test "verify email with invalid username" do
      conn =
        get(build_conn(), "email/verify", %{username: "invalid", email: "invalid", key: "invalid"})

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :error) =~ "failed to verify"
    end

    test "verify email with valid key", c do
      email = hd(c.user.emails)

      conn =
        get(build_conn(), "email/verify", %{
          username: c.user.username,
          email: email.email,
          key: email.verification_key
        })

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "has been verified"

      user = Users.get(c.user.username, [:emails])
      assert hd(user.emails).verified
    end
  end

  describe "GET /email/verification" do
    test "show verification form" do
      conn = get(build_conn(), "email/verification")
      assert response(conn, 200) =~ "Verify email"
    end
  end

  describe "POST /email/verification" do
    test "send verification email" do
      user = insert(:user, emails: [build(:email, verified: false)])
      email = User.email(user, :primary)

      conn = post(build_conn(), "email/verification", %{"email" => email})
      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "A verification email has been sent"

      user = Users.get(user.username, [:emails])
      assert_delivered_email(Hexpm.Emails.verification(user, hd(user.emails)))
      assert hd(user.emails).verification_key
    end

    test "dont send verification email for already verified email" do
      user = insert(:user, emails: [build(:email, verified: true)])
      email = User.email(user, :primary)

      conn = post(build_conn(), "email/verification", %{"email" => email})
      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "A verification email has been sent"

      user = Users.get(user.username, [:emails])
      refute_delivered_email(Hexpm.Emails.verification(user, hd(user.emails)))
      refute hd(user.emails).verification_key
    end

    test "dont send verification email for non-existent email" do
      conn = post(build_conn(), "email/verification", %{"email" => "foo@example.com"})
      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "A verification email has been sent"
    end
  end
end
