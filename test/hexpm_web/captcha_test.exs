defmodule HexpmWeb.CaptchaTest do
  use HexpmWeb.ConnCase

  alias Hexpm.Accounts.Users
  alias HexpmWeb.Captcha

  setup :verify_on_exit!

  @failure Jason.decode!(~s/{"success":false,"error-codes":["invalid-input-response"]}/)
  @success Jason.decode!(~s/{"success":true}/)

  test "returns false for non-success response" do
    expect(
      Hexpm.HTTP.Mock,
      :post,
      fn "https://hcaptcha.com/siteverify", headers, params ->
        assert headers == [{"content-type", "application/x-www-form-urlencoded"}]
        assert params == %{response: "bad", secret: "secret"}
        {:ok, 200, [{"content-type", "application/json"}], @failure}
      end
    )

    refute Captcha.verify("bad")
  end

  test "returns true for successful response" do
    expect(
      Hexpm.HTTP.Mock,
      :post,
      fn "https://hcaptcha.com/siteverify", headers, params ->
        assert headers == [{"content-type", "application/x-www-form-urlencoded"}]
        assert params == %{response: "good", secret: "secret"}
        {:ok, 200, [{"content-type", "application/json"}], @success}
      end
    )

    assert Captcha.verify("good")
  end

  test "returns true when disabled" do
    app_env(:hexpm, :hcaptcha, sitekey: nil)
    assert Captcha.verify("disabled")
  end

  test "returns true with missing token when disabled" do
    app_env(:hexpm, :hcaptcha, nil)
    assert Captcha.verify(nil)
  end

  test "POST /signup creates user when captcha is disabled" do
    app_env(:hexpm, :hcaptcha, nil)

    username = Fake.sequence(:username)
    email = Fake.sequence(:email)

    conn =
      post(build_conn(), "/signup", %{
        "user" => %{
          "username" => username,
          "emails" => %{
            "0" => %{
              "email" => email,
              "email_confirmation" => email
            }
          },
          "password" => "hunter42",
          "password_confirmation" => "hunter42",
          "full_name" => "José"
        }
      })

    assert redirected_to(conn) == "/"
    assert Users.get(username).username == username
  end
end
