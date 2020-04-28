defmodule Hexpm.ShortURLsTest do
  use Hexpm.DataCase, async: true
  alias Hexpm.ShortURLs
  alias Hexpm.ShortURLs.ShortURL

  describe "add/1" do
    test "with correct params, creates a new short url" do
      url = "https://diff.hex.pm?diff[]=ecto:3.0.1:3.0.4"
      params = %{"url" => url}
      {:ok, short_url} = ShortURLs.add(params)
      assert short_url.short_code
      assert short_url.url == url
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
