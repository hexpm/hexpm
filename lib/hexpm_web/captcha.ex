defmodule HexpmWeb.Captcha do
  alias Hexpm.HTTP
  require Logger

  @verify_endpoint "https://hcaptcha.com/siteverify"

  def enabled? do
    sitekey() != nil
  end

  def verify(token) do
    if enabled?() do
      headers = [{"content-type", "application/x-www-form-urlencoded"}]
      params = %{response: token, secret: secret()}

      case HTTP.impl().post(@verify_endpoint, headers, params) do
        {:ok, 200, _headers, %{"success" => success}} ->
          success

        {:error, reason} ->
          Logger.error("hcaptcha request failed: #{inspect(reason)}")
          false
      end
    else
      true
    end
  end

  def sitekey() do
    Application.get_env(:hexpm, :hcaptcha, [])[:sitekey]
  end

  defp secret() do
    Application.get_env(:hexpm, :hcaptcha, [])[:secret]
  end
end
