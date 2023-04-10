defmodule HexpmWeb.SignupControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.Accounts.Users

  describe "GET /signup" do
    test "show create user page" do
      conn = get(build_conn(), "/signup")
      assert response(conn, 200) =~ "Sign up"
    end
  end

  describe "POST /signup" do
    setup :mock_captcha_success

    test "create user" do
      username = Fake.sequence(:username)

      conn =
        post(build_conn(), "/signup", %{
          "user" => %{
            "username" => username,
            "emails" => [%{"email" => Fake.sequence(:email)}],
            "password" => "hunter42",
            "full_name" => "José"
          },
          "h-captcha-response" => "captcha"
        })

      assert redirected_to(conn) == "/"
      user = Users.get(username)
      assert user.username == username
      assert user.full_name == "José"
    end

    test "create user invalid" do
      user = insert(:user)

      conn =
        post(build_conn(), "/signup", %{
          "user" => %{
            "username" => user.username,
            "emails" => [%{"email" => Fake.sequence(:email)}],
            "password" => "hunter42",
            "full_name" => "José"
          },
          "h-captcha-response" => "captcha"
        })

      assert response(conn, 400) =~ "Sign up"
      assert conn.resp_body =~ "Oops, something went wrong!"
    end
  end

  test "POST /signup captha failed" do
    mock_captcha_failure()

    conn =
      post(build_conn(), "/signup", %{
        "user" => %{
          "username" => Fake.sequence(:username),
          "emails" => [%{"email" => Fake.sequence(:email)}],
          "password" => "hunter42",
          "full_name" => "José"
        },
        "h-captcha-response" => "captcha"
      })

    assert response(conn, 400) =~ "Please complete the captcha to sign up"
  end
end
