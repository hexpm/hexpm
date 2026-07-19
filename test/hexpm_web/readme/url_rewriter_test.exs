defmodule HexpmWeb.Readme.URLRewriterTest do
  use ExUnit.Case, async: true

  alias HexpmWeb.Readme.URLRewriter

  defp rewrite(html, package, version) do
    html
    |> Floki.parse_document!()
    |> URLRewriter.rewrite("hexpm", package, version)
    |> Floki.raw_html()
  end

  describe "rewrite/3" do
    test "rewrites absolute image URLs to proxy" do
      html = ~s[<img src="https://example.com/logo.png">]
      result = rewrite(html, "my_package", "1.0.0")

      assert result =~ "http://localhost:5000/img/fetch/"
      refute result =~ ~s[src="https://example.com/logo.png"]
    end

    test "resolves relative image paths to preview URL and proxies them" do
      html = ~s[<img src="docs/logo.png">]
      result = rewrite(html, "my_package", "1.0.0")

      expected = "http://localhost:5000/preview/my_package/1.0.0/docs/logo.png"
      encoded = Base.encode16(expected, case: :lower)
      assert result =~ encoded
    end

    test "resolves relative link paths to preview URL" do
      html = ~s[<a href="CHANGELOG.md">Changelog</a>]
      result = rewrite(html, "my_package", "1.0.0")

      assert result =~ "http://localhost:5000/preview/my_package/1.0.0/CHANGELOG.md"
    end

    test "resolves private package relative links to the raw endpoint" do
      html = ~s[<a href="CHANGELOG.md">Changelog</a>]

      result =
        html
        |> Floki.parse_document!()
        |> URLRewriter.rewrite("acme", "my_package", "1.0.0")
        |> Floki.raw_html()

      assert result =~
               HexpmWeb.Endpoint.url() <> "/packages/acme/my_package/1.0.0/raw/CHANGELOG.md"
    end

    test "resolves private package relative images to a tokenized image endpoint via the proxy" do
      html = ~s[<img src="docs/logo.png">]

      result =
        html
        |> Floki.parse_document!()
        |> URLRewriter.rewrite("acme", "my_package", "1.0.0")
        |> Floki.raw_html()

      [proxied] =
        result
        |> Floki.parse_fragment!()
        |> Floki.attribute("img", "src")

      assert String.starts_with?(proxied, Application.fetch_env!(:hexpm, :img_url) <> "/fetch/")

      encoded = proxied |> String.split("/") |> List.last()
      decoded = Base.decode16!(encoded, case: :lower)

      assert String.starts_with?(
               decoded,
               HexpmWeb.Endpoint.url() <>
                 "/packages/acme/my_package/1.0.0/readme-image/docs/logo.png?token="
             )

      token = decoded |> String.split("token=") |> List.last()
      assert HexpmWeb.ReadmeToken.verify(token, "acme", "my_package", "1.0.0") == :ok
    end

    test "prefixes fragment-only links with user-content-" do
      html = ~s[<a href="#installation">Install</a>]
      result = rewrite(html, "my_package", "1.0.0")

      assert result =~ ~s[href="#user-content-installation"]
    end

    test "preserves footnote fragment links unchanged" do
      html = ~s[<a href="#fn-1">1</a><a href="#fnref-1">back</a>]
      result = rewrite(html, "my_package", "1.0.0")

      assert result =~ ~s[href="#fn-1"]
      assert result =~ ~s[href="#fnref-1"]
    end

    test "preserves named footnote fragment links unchanged" do
      html = ~s[<a href="#fn-note">1</a><a href="#fnref-note">back</a>]
      result = rewrite(html, "my_package", "1.0.0")

      assert result =~ ~s[href="#fn-note"]
      assert result =~ ~s[href="#fnref-note"]
    end

    test "preserves absolute link URLs" do
      html = ~s[<a href="https://hexdocs.pm/phoenix">Phoenix</a>]
      result = rewrite(html, "my_package", "1.0.0")

      assert result =~ ~s[href="https://hexdocs.pm/phoenix"]
    end

    test "strips ./ prefix from relative paths" do
      html = ~s[<img src="./images/logo.png">]
      result = rewrite(html, "my_package", "1.0.0")

      expected = "http://localhost:5000/preview/my_package/1.0.0/images/logo.png"
      encoded = Base.encode16(expected, case: :lower)
      assert result =~ encoded
    end

    test "adds color-scheme-light class for gh-light-mode-only fragment" do
      html = ~s[<img src="https://example.com/logo.png#gh-light-mode-only" alt="Logo">]
      result = rewrite(html, "my_package", "1.0.0")

      assert result =~ ~s[class="color-scheme-light"]
      # Fragment should be stripped from the proxied URL
      refute result =~ "gh-light-mode-only"
    end

    test "adds color-scheme-dark class for gh-dark-mode-only fragment" do
      html = ~s[<img src="https://example.com/logo.png#gh-dark-mode-only" alt="Logo">]
      result = rewrite(html, "my_package", "1.0.0")

      assert result =~ ~s[class="color-scheme-dark"]
      refute result =~ "gh-dark-mode-only"
    end

    test "does not add class for other fragments on images" do
      html = ~s[<img src="https://example.com/logo.png#section" alt="Logo">]
      result = rewrite(html, "my_package", "1.0.0")

      refute result =~ ~s[class="]
    end

    test "handles img tag without src attribute" do
      html = ~s[<img alt="Logo">]
      result = rewrite(html, "my_package", "1.0.0")

      assert result =~ ~s[alt="Logo"]
      refute result =~ "src="
    end

    test "does not proxy non-http/https image URLs" do
      html = ~s[<img src="data:image/png;base64,abc123">]
      result = rewrite(html, "my_package", "1.0.0")

      assert result =~ ~s[src="data:image/png;base64,abc123"]
    end

    test "proxies protocol-relative image URLs" do
      html = ~s[<img src="//example.com/logo.png">]
      result = rewrite(html, "my_package", "1.0.0")

      expected = "https://example.com/logo.png"
      encoded = Base.encode16(expected, case: :lower)
      assert result =~ encoded
      assert result =~ "http://localhost:5000/img/fetch/"
    end

    test "resolves protocol-relative link URLs" do
      html = ~s[<a href="//example.com/docs">Docs</a>]
      result = rewrite(html, "my_package", "1.0.0")

      assert result =~ ~s[href="https://example.com/docs"]
    end

    test "normalizes path traversal in relative URLs" do
      html = ~s[<a href="./foo/../bar/baz">Link</a>]
      result = rewrite(html, "my_package", "1.0.0")

      assert result =~ "http://localhost:5000/preview/my_package/1.0.0/bar/baz"
      refute result =~ ".."
    end

    test "rejects path traversal escaping the base directory" do
      html = ~s[<a href="../../etc/passwd">Link</a>]
      result = rewrite(html, "my_package", "1.0.0")

      refute result =~ "preview"
      assert result =~ ~s[href="../../etc/passwd"]
    end

    test "resolves absolute image paths to preview URL and proxies them" do
      html = ~s[<img src="/images/examples.png">]
      result = rewrite(html, "my_package", "1.0.0")

      expected = "http://localhost:5000/preview/my_package/1.0.0/images/examples.png"
      encoded = Base.encode16(expected, case: :lower)
      assert result =~ encoded
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
