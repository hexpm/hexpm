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

      expected = "http://localhost:5000/preview/my_package/1.0.0/docs/logo.png"
      encoded = Base.encode16(expected, case: :lower)
      assert result =~ encoded
    end

    test "resolves relative link paths to preview URL" do
      html = ~s[<a href="CHANGELOG.md">Changelog</a>]
      result = URLRewriter.rewrite(html, "my_package", "1.0.0")

      assert result =~ "http://localhost:5000/preview/my_package/1.0.0/CHANGELOG.md"
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

      expected = "http://localhost:5000/preview/my_package/1.0.0/images/logo.png"
      encoded = Base.encode16(expected, case: :lower)
      assert result =~ encoded
    end

    test "adds color-scheme-light class for gh-light-mode-only fragment" do
      html = ~s[<img src="https://example.com/logo.png#gh-light-mode-only" alt="Logo">]
      result = URLRewriter.rewrite(html, "my_package", "1.0.0")

      assert result =~ ~s[class="color-scheme-light"]
      # Fragment should be stripped from the proxied URL
      refute result =~ "gh-light-mode-only"
    end

    test "adds color-scheme-dark class for gh-dark-mode-only fragment" do
      html = ~s[<img src="https://example.com/logo.png#gh-dark-mode-only" alt="Logo">]
      result = URLRewriter.rewrite(html, "my_package", "1.0.0")

      assert result =~ ~s[class="color-scheme-dark"]
      refute result =~ "gh-dark-mode-only"
    end

    test "does not add class for other fragments on images" do
      html = ~s[<img src="https://example.com/logo.png#section" alt="Logo">]
      result = URLRewriter.rewrite(html, "my_package", "1.0.0")

      refute result =~ ~s[class="]
    end

    test "handles img tag without src attribute" do
      html = ~s[<img alt="Logo">]
      result = URLRewriter.rewrite(html, "my_package", "1.0.0")

      assert result =~ ~s[alt="Logo"]
      refute result =~ "src="
    end

    test "does not proxy non-http/https image URLs" do
      html = ~s[<img src="data:image/png;base64,abc123">]
      result = URLRewriter.rewrite(html, "my_package", "1.0.0")

      assert result =~ ~s[src="data:image/png;base64,abc123"]
    end

    test "proxies protocol-relative image URLs" do
      html = ~s[<img src="//example.com/logo.png">]
      result = URLRewriter.rewrite(html, "my_package", "1.0.0")

      expected = "https://example.com/logo.png"
      encoded = Base.encode16(expected, case: :lower)
      assert result =~ encoded
      assert result =~ "http://localhost:5000/img/fetch/"
    end

    test "resolves protocol-relative link URLs" do
      html = ~s[<a href="//example.com/docs">Docs</a>]
      result = URLRewriter.rewrite(html, "my_package", "1.0.0")

      assert result =~ ~s[href="https://example.com/docs"]
    end

    test "normalizes path traversal in relative URLs" do
      html = ~s[<a href="./foo/../bar/baz">Link</a>]
      result = URLRewriter.rewrite(html, "my_package", "1.0.0")

      assert result =~ "http://localhost:5000/preview/my_package/1.0.0/bar/baz"
      refute result =~ ".."
    end

    test "rejects path traversal escaping the base directory" do
      html = ~s[<a href="../../etc/passwd">Link</a>]
      result = URLRewriter.rewrite(html, "my_package", "1.0.0")

      refute result =~ "preview"
      assert result =~ ~s[href="../../etc/passwd"]
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
