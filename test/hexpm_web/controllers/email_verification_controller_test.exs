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
        get(build_conn(), "/email/verify", %{
          username: c.user.username,
          email: email.email,
          key: "invalid"
        })

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "failed to verify"

      user = Users.get(c.user.username, [:emails])
      refute hd(user.emails).verified
    end

    test "verify email with invalid username" do
      conn =
        get(build_conn(), "/email/verify", %{
          username: "invalid",
          email: "invalid",
          key: "invalid"
        })

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "failed to verify"
    end

    test "verify email with valid key", c do
      email = hd(c.user.emails)

      conn =
        get(build_conn(), "/email/verify", %{
          username: c.user.username,
          email: email.email,
          key: email.verification_key
        })

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "has been verified"

      user = Users.get(c.user.username, [:emails])
      assert hd(user.emails).verified
    end
  end

  describe "GET /email/verification" do
    test "show verification form" do
      conn = get(build_conn(), "/email/verification")
      assert response(conn, 200) =~ "Verify email"
    end
  end

  describe "POST /email/verification" do
    setup :mock_captcha_success

    test "send verification email" do
      user = insert(:user, emails: [build(:email, verified: false)])
      email = User.email(user, :primary)

      conn =
        post(build_conn(), "/email/verification", %{
          "username" => user.username,
          "email" => email,
          "h-captcha-response" => "captcha"
        })

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "A verification email has been sent"

      user = Users.get(user.username, [:emails])
      assert_delivered_email(Hexpm.Emails.verification(user, hd(user.emails)))
      assert hd(user.emails).verification_key
    end

    test "dont send verification email for already verified email" do
      user = insert(:user, emails: [build(:email, verified: true)])
      email = User.email(user, :primary)

      conn =
        post(build_conn(), "/email/verification", %{
          "username" => user.username,
          "email" => email,
          "h-captcha-response" => "captcha"
        })

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "A verification email has been sent"

      user = Users.get(user.username, [:emails])

      refute_delivered_email(
        Hexpm.Emails.verification(user, %{hd(user.emails) | verification_key: "key"})
      )

      refute hd(user.emails).verification_key
    end

    test "dont send verification email for non-existent email" do
      user = insert(:user)

      conn =
        post(build_conn(), "/email/verification", %{
          "username" => user.username,
          "email" => "foo@example.com",
          "h-captcha-response" => "captcha"
        })

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "A verification email has been sent"
    end

    test "dont send verification email for wrong user" do
      user1 = insert(:user, emails: [build(:email, verified: false)])
      user2 = insert(:user, emails: [build(:email, verified: false)])
      email = User.email(user2, :primary)

      conn =
        post(build_conn(), "/email/verification", %{
          "username" => user1.username,
          "email" => email,
          "h-captcha-response" => "captcha"
        })

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "A verification email has been sent"

      refute_delivered_email(
        Hexpm.Emails.verification(user1, %{hd(user1.emails) | verification_key: "key"})
      )

      refute_delivered_email(
        Hexpm.Emails.verification(user2, %{hd(user2.emails) | verification_key: "key"})
      )

      user1 = Users.get(user1.username, [:emails])
      refute hd(user1.emails).verification_key

      user2 = Users.get(user2.username, [:emails])

      refute hd(user2.emails).verification_key
    end
  end

  test "POST /email/verification captha failed" do
    mock_captcha_failure()

    user = insert(:user, emails: [build(:email, verified: false)])
    email = User.email(user, :primary)

    conn =
      post(build_conn(), "/email/verification", %{
        "username" => user.username,
        "email" => email,
        "h-captcha-response" => "captcha"
      })

    assert response(conn, 400) =~ "Please complete the captcha to send verification email"
  end
end
