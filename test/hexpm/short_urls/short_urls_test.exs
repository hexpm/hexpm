defmodule Hexpm.ShortURLsTest do
  use Hexpm.DataCase, async: true
  alias Hexpm.ShortURLs
  alias Hexpm.ShortURLs.ShortURL

  describe "add/1" do
    test "with correct params, creates a new short url for *.hex.pm" do
      url = "https://diff.hex.pm?diff[]=ecto:3.0.1:3.0.4"
      params = %{"url" => url}
      {:ok, short_url} = ShortURLs.add(params)
      assert short_url.short_code
      assert short_url.url == url
    end

    test "with correct params, creates a new short url for hex.pm" do
      url = "https://hex.pm?diff[]=ecto:3.0.1:3.0.4"
      params = %{"url" => url}
      {:ok, short_url} = ShortURLs.add(params)
      assert short_url.short_code
      assert short_url.url == url
    end

    test "with incorrect params, errors instead of creating a new short url" do
      url = "https://ATTACKDOMAINhex.pm/derp"
      params = %{"url" => url}
      assert {:error, %{valid?: false}} = ShortURLs.add(params)
    end

    # `URI.parse/1` ends the authority at the first "/", "?" or "#", a browser
    # also ends it at a "\\" and drops tabs and newlines first, and both split
    # userinfo at the "@". Every spelling that reads as one host here and
    # another one there is refused rather than reconciled.
    for {label, url} <- [
          {"backslash before the allowed host", "https://evil.example\\@hex.pm/"},
          {"encoded backslash", "https://evil.example%5c@hex.pm/"},
          {"tab", "https://evil.example\t@hex.pm/"},
          {"carriage return", "https://evil.example\r@hex.pm/"},
          {"space", "https://evil.example @hex.pm/"},
          {"userinfo", "https://user@hex.pm/"},
          {"encoded separator in the host", "https://evil.com%2f.hex.pm/"},
          {"IPv6 literal as userinfo", "https://[::1]@hex.pm/"},
          {"allowed host as userinfo", "https://hex.pm@evil.com/"},
          {"non-default port", "https://hex.pm:8443/"},
          {"tab inside the port", "https://hex.pm:443\t0/"},
          {"newline inside the host", "https://hex\n.pm/"}
        ] do
      test "refuses a URL with a #{label}" do
        assert {:error, %{valid?: false}} = ShortURLs.add(%{"url" => unquote(url)})
      end
    end
  end

  describe "redirect_url/1" do
    test "rebuilds the target from the parsed host and path" do
      short_url = %ShortURL{url: "https://diff.hex.pm/diff/ecto/3.0.1..3.0.4"}

      assert ShortURL.redirect_url(short_url) == "https://diff.hex.pm/diff/ecto/3.0.1..3.0.4"
    end

    test "refuses a stored URL that does not pass validation" do
      short_url = %ShortURL{url: "https://evil.example\\@hex.pm/"}

      refute ShortURL.redirect_url(short_url)
    end
  end

  describe "get/1" do
    setup do
      Repo.insert(%ShortURL{
        short_code: "abcde",
        url: "https://diff.hex.pm?diff[]=ecto:3.0.1:3.0.4"
      })

      :ok
    end

    test "given a short_code that exists, returns a record" do
      assert ShortURLs.get("abcde")
    end

    test "given a short_code that does not exist, returns nil" do
      refute ShortURLs.get("zyxwv")
    end
  end
end
