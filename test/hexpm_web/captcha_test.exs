defmodule HexpmWeb.CaptchaTest do
  use HexpmWeb.ConnCase
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
end
