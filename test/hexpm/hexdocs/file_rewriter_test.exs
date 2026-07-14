defmodule Hexpm.Hexdocs.FileRewriterTest do
  use ExUnit.Case, async: true

  alias Hexpm.Hexdocs.FileRewriter

  test "adds analytics and removes noindex from HTML" do
    rewritten =
      FileRewriter.run(
        "index.html",
        ~s(<html><head><meta name="robots" content="noindex"></head></html>)
      )

    assert rewritten =~ ~s(src="https://s.localhost/js/script.js")
    refute rewritten =~ ~s(content="noindex")
  end

  test "rewrites canonical package URLs to package subdomains" do
    input =
      ~s|<link rel="canonical" href="https://hexdocs.pm/phoenix_html/1.0.0/Phoenix.HTML.html"/>|

    assert FileRewriter.run("index.html", input) ==
             ~s|<link rel="canonical" href="https://phoenix-html.hexdocs.pm/1.0.0/Phoenix.HTML.html"/>|
  end

  test "does not rewrite body links, apex files, or existing subdomains" do
    for input <- [
          ~s|<a href="https://hexdocs.pm/jason/Jason.html">Jason</a>|,
          ~s|<link rel="canonical" href="https://hexdocs.pm/sitemap.xml"/>|,
          ~s|<link rel="canonical" href="https://jason.hexdocs.pm/Jason.html"/>|
        ] do
      assert FileRewriter.run("index.html", input) == input
    end
  end

  test "adds nofollow only to external links and remains idempotent" do
    external = ~s|<a href="https://example.com" rel="help">example</a>|
    rewritten = FileRewriter.run("index.html", external)

    assert rewritten == ~s|<a href="https://example.com" rel="help nofollow">example</a>|
    assert FileRewriter.run("index.html", rewritten) == rewritten

    official = ~s|<a href="https://preview.hexdocs.pm/foo">docs</a>|
    assert FileRewriter.run("index.html", official) == official
  end

  test "does not modify non-HTML files" do
    input = ~s|<a href="https://example.com">example</a>|
    assert FileRewriter.run("app.js", input) == input
  end
end
