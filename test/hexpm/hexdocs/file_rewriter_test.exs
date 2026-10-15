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

  test "adds analytics once, before the first </head>" do
    snippet = ~s(<script async defer src="https://s.localhost/js/script.js">)

    for {input, before} <- [
          {"<html><head></head><head></head></html>", "</head><head></head></html>"}
        ] do
      rewritten = FileRewriter.run("index.html", input)
      assert [_, after_snippet] = String.split(rewritten, snippet)
      assert String.ends_with?(after_snippet, before)
    end
  end

  test "a page of </head> tags grows by one analytics snippet" do
    page = String.duplicate("</head>", 150_000)
    rewritten = FileRewriter.run("index.html", page)

    assert byte_size(rewritten) ==
             byte_size(page) + byte_size(FileRewriter.run("index.html", "</head>")) - 7
  end

  test "pages of unterminated tags come back unchanged" do
    for token <- ["<", "<a ", "<link ", "<a href=", "<a href=\"", "<a rel='"] do
      page = String.duplicate(token, div(1_048_576, byte_size(token)))
      assert FileRewriter.run("index.html", page) == page
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

  test "removes canonical tags whatever their attribute syntax" do
    for input <- [
          ~s|<link rel=canonical href="https://example.com/">|,
          ~s|<LINK REL="CANONICAL" HREF="https://example.com/">|,
          ~s|<link title=">" rel="canonical" href="https://example.com/">|,
          ~s|<link rel="canonical" rel="stylesheet" href="https://example.com/">|,
          ~s|<link/rel="canonical"/href="https://example.com/">|
        ] do
      assert FileRewriter.run("index.html", ~s|<head>#{input}\n</head>|) =~ ~r"\A<head><script"
    end
  end

  test "keeps a link tag whose first rel isn't canonical" do
    input = ~s|<link rel="stylesheet" rel="canonical" href="app.css">|
    assert FileRewriter.run("index.html", input) == input
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

  test "adds nofollow to external links whatever their syntax" do
    for {input, expected} <- [
          {~s|<a href='https://example.com'>|, ~s|<a rel="nofollow" href='https://example.com'>|},
          {~s|<A HREF="https://example.com">|, ~s|<A rel="nofollow" HREF="https://example.com">|},
          {~s|<a href=https://example.com>|, ~s|<a rel="nofollow" href=https://example.com>|},
          {~s|<a title=">" href="https://example.com">|,
           ~s|<a rel="nofollow" title=">" href="https://example.com">|},
          {~s|<a href="//example.com">|, ~s|<a rel="nofollow" href="//example.com">|},
          {~s|<a href="/\\example.com">|, ~s|<a rel="nofollow" href="/\\example.com">|},
          {~s|<a href=" HTTPS://example.com">|,
           ~s|<a rel="nofollow" href=" HTTPS://example.com">|},
          {~s|<a href="https&#58;//example.com">|,
           ~s|<a rel="nofollow" href="https&#58;//example.com">|},
          {~s|<a href="https://hexdocs.pm.example.com">|,
           ~s|<a rel="nofollow" href="https://hexdocs.pm.example.com">|},
          {~s|<a href="https://hexdocs.pm@example.com">|,
           ~s|<a rel="nofollow" href="https://hexdocs.pm@example.com">|},
          {~s|<a rel href="https://example.com">|,
           ~s|<a rel="nofollow" href="https://example.com">|},
          {~s|<a rel="" href="https://example.com">|,
           ~s|<a rel="nofollow" href="https://example.com">|},
          {~s|<a rel=help href="https://example.com">|,
           ~s|<a rel="help nofollow" href="https://example.com">|},
          {~s|<a rel='help"' href="https://example.com">|,
           ~s|<a rel="help&quot; nofollow" href="https://example.com">|},
          {~s|<a rel="help" rel="nofollow" href="https://example.com">|,
           ~s|<a rel="help nofollow" rel="nofollow" href="https://example.com">|}
        ] do
      assert FileRewriter.run("index.html", input) == expected
      assert FileRewriter.run("index.html", expected) == expected
    end
  end

  test "leaves relative, official and already nofollow links alone" do
    for input <- [
          ~s|<a href="Jason.html#decode/2">|,
          ~s|<a href="#content">|,
          ~s|<a href="https://HEXDOCS.PM/jason">|,
          ~s|<a href="//hex.pm/packages/jason">|,
          ~s|<a href="https://www.erlang.org/doc">|,
          ~s|<a rel="NOFOLLOW" href="https://example.com">|
        ] do
      assert FileRewriter.run("index.html", input) == input
    end
  end

  test "rewrites every page served as HTML" do
    input = ~s|<a href="https://example.com">example</a>|
    expected = ~s|<a rel="nofollow" href="https://example.com">example</a>|

    for path <- ~w(index.html index.htm INDEX.HTML) do
      assert FileRewriter.run(path, input) == expected
    end
  end

  @tag :tmp_dir
  test "rewrite_files rewrites the HTML files in place", %{tmp_dir: dir} do
    link = ~s|<a href="https://example.com">example</a>|
    page = String.duplicate(link, 3000)
    File.write!(Path.join(dir, "index.html"), page)
    File.write!(Path.join(dir, "app.js"), link)

    assert :ok = FileRewriter.rewrite_files(dir, ["index.html", "app.js"])

    assert File.read!(Path.join(dir, "index.html")) == FileRewriter.run("index.html", page)
    assert File.read!(Path.join(dir, "app.js")) == link
  end

  test "does not modify non-HTML files" do
    input = ~s|<a href="https://example.com">example</a>|
    assert FileRewriter.run("app.js", input) == input
  end
end
