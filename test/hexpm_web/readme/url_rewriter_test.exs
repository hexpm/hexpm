defmodule HexpmWeb.Readme.URLRewriterTest do
  use ExUnit.Case, async: true

  alias HexpmWeb.Readme.URLRewriter

  describe "rewrite/3" do
    test "rewrites absolute image URLs to proxy" do
      html = ~s[<img src="https://example.com/logo.png">]
      result = URLRewriter.rewrite(html, "my_package", "1.0.0")

      assert result =~ "http://localhost:5000/img/fetch/"
      refute result =~ ~s[src="https://example.com/logo.png"]
    end

    test "resolves relative image paths to preview URL and proxies them" do
      html = ~s[<img src="docs/logo.png">]
      result = URLRewriter.rewrite(html, "my_package", "1.0.0")

      expected = "http://localhost:5005/preview/my_package/1.0.0/docs/logo.png"
      encoded = Base.encode16(expected, case: :lower)
      assert result =~ encoded
    end

    test "resolves relative link paths to preview URL" do
      html = ~s[<a href="CHANGELOG.md">Changelog</a>]
      result = URLRewriter.rewrite(html, "my_package", "1.0.0")

      assert result =~ "http://localhost:5005/preview/my_package/1.0.0/CHANGELOG.md"
    end

    test "preserves fragment-only links" do
      html = ~s[<a href="#installation">Install</a>]
      result = URLRewriter.rewrite(html, "my_package", "1.0.0")

      assert result =~ ~s[href="#installation"]
    end

    test "preserves absolute link URLs" do
      html = ~s[<a href="https://hexdocs.pm/phoenix">Phoenix</a>]
      result = URLRewriter.rewrite(html, "my_package", "1.0.0")

      assert result =~ ~s[href="https://hexdocs.pm/phoenix"]
    end

    test "strips ./ prefix from relative paths" do
      html = ~s[<img src="./images/logo.png">]
      result = URLRewriter.rewrite(html, "my_package", "1.0.0")

      expected = "http://localhost:5005/preview/my_package/1.0.0/images/logo.png"
      encoded = Base.encode16(expected, case: :lower)
      assert result =~ encoded
    end

    test "does not proxy non-http/https image URLs" do
      html = ~s[<img src="data:image/png;base64,abc123">]
      result = URLRewriter.rewrite(html, "my_package", "1.0.0")

      assert result =~ ~s[src="data:image/png;base64,abc123"]
    end
  end

  describe "proxy_image_url/1" do
    test "generates HMAC-signed proxy URL" do
      url = "https://example.com/image.png"
      result = URLRewriter.proxy_image_url(url)

      assert result =~ "http://localhost:5000/img/fetch/"
      encoded = Base.encode16(url, case: :lower)
      assert result =~ encoded
    end

    test "passes through non-http URLs" do
      assert URLRewriter.proxy_image_url("#fragment") == "#fragment"
    end
  end
end
