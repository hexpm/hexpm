defmodule Hexpm.Hexdocs.FileRewriterTest do
  use ExUnit.Case, async: true

  alias Hexpm.Hexdocs.FileRewriter

  test "adds analytics to HTML and keeps noindex" do
    for path <- ~w(search.html 404.html api-reference.html) do
      rewritten =
        FileRewriter.run(
          path,
          ~s(<html><head><meta name="robots" content="noindex"></head></html>)
        )

      assert rewritten =~ ~s(src="https://s.localhost/js/script.js")
      assert rewritten =~ ~s(content="noindex")
    end
  end

  test "removes canonical tags whatever the author pointed them at" do
    for input <- [
          ~s|<link rel="canonical" href="https://hexdocs.pm/phoenix_html/1.0.0/Phoenix.HTML.html"/>|,
          ~s|<link rel="canonical" href="http://hexdocs.pm/jason/Jason.html" />|,
          ~s|<link rel='canonical' href='https://jason.hexdocs.pm/Jason.html'>|,
          ~s|<link\n  href="https://hexdocs.pm/jason/Jason.html"\n  rel="canonical">|
        ] do
      assert FileRewriter.run("index.html", ~s|<body>#{input}<p>Jason</p></body>|) ==
               "<body><p>Jason</p></body>"
    end
  end

  test "leaves other link tags and body links alone" do
    for input <- [
          ~s|<a href="https://hexdocs.pm/jason/Jason.html">Jason</a>|,
          ~s|<link rel="stylesheet" href="dist/canonical-ABC123.css"/>|,
          ~s|<link rel="icon" href="/favicon.ico">|
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
