defmodule Hexpm.Hexdocs.FileRewriterTest do
  use ExUnit.Case, async: true

  alias Hexpm.Hexdocs.FileRewriter

  test "adds analytics to HTML and keeps noindex" do
    rewritten =
      FileRewriter.run(
        "search.html",
        ~s(<html><head><meta name="robots" content="noindex"></head></html>)
      )

    assert rewritten =~ ~s(src="https://s.localhost/js/script.js")
    assert rewritten =~ ~s(content="noindex")
  end

  test "removes canonical tags whatever the author pointed them at" do
    for input <- [
          ~s|<link rel="canonical" href="https://hexdocs.pm/phoenix_html/1.0.0/Phoenix.HTML.html"/>|,
          ~s|<link rel="canonical" href="http://hexdocs.pm/jason/Jason.html" />|,
          ~s|<link rel='canonical' href='https://jason.hexdocs.pm/Jason.html'>|
        ] do
      refute FileRewriter.run("index.html", ~s|<body>#{input}</body>|) =~ "canonical"
    end
  end

  test "leaves body links to hexdocs alone" do
    input = ~s|<a href="https://hexdocs.pm/jason/Jason.html">Jason</a>|
    assert FileRewriter.run("index.html", input) == input
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
