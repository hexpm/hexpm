defmodule HexpmWeb.SyntaxHighlight.OutputTest do
  use ExUnit.Case, async: true

  alias HexpmWeb.SyntaxHighlight.{Output, Pool}

  @samples %{
    "lib/app.ex" => ~S'''
    defmodule App do
      @moduledoc "<b>#{1 + 1}</b>"
      def run(%{value: value} = map) when is_map(map), do: ~H"<p>{value}</p>"
    end
    ''',
    "src/app.erl" => "-module(app).\n-export([run/1]).\nrun(X) -> <<X:8>>.\n",
    "README.md" =>
      "# Title\n\n```elixir\nIO.puts(:ok)\n```\n\n<script>alert(1)</script>\n\n```js\nlet a = '</code>'\n```\n",
    "index.html" =>
      ~s(<!doctype html>\n<html><script>let x = "</pre>";</script><style>a { color: red }</style></html>\n),
    "data.json" => ~s({"key": ["<", ">", "&", "\\""]}\n),
    "notes.unknown-extension" => "a < b && c > d\n"
  }

  test "accepts what lumis serve writes" do
    for {path, source} <- @samples do
      assert {:ok, html} = Pool.highlight(source, path)
      assert Output.valid?(html), "rejected the output for #{path}: #{html}"
    end
  end

  test "accepts the tags html-linked writes" do
    assert Output.valid?(
             ~s(<pre class="lumis"><code class="language-elixir" translate="no" tabindex="0">) <>
               ~s(<div class="l-line" data-line="1"><span class="l-keyword-function">def</span> &lt;x&gt;\n</div>) <>
               "</code></pre>"
           )

    assert Output.valid?("")
    assert Output.valid?("plain text & more")
  end

  test "rejects any other tag or attribute" do
    for html <- [
          "<script>alert(1)</script>",
          ~S|<span class="l-x" onclick="alert(1)">x</span>|,
          ~S|<span class="l-x"><img src=x onerror=alert(1)></span>|,
          ~S|<span class="other">x</span>|,
          ~S|<span class="l-x" >x</span>|,
          ~S|<span class='l-x'>x</span>|,
          ~S|<div class="l-line" data-line="1" style="color: red">x</div>|,
          ~S|<code class="language-x" translate="no" tabindex="0" autofocus>|,
          ~S|<pre class="lumis other">|,
          ~S|<a href="https://hex.pm">x</a>|,
          "<!-- comment -->",
          "<"
        ] do
      refute Output.valid?(html), "accepted #{html}"
    end
  end

  test "rejects tags closed out of order or never opened" do
    refute Output.valid?(~s(<span class="l-x">x</div>))
    refute Output.valid?("</div><script>")
    refute Output.valid?("</div>text")
    refute Output.valid?(~s(<div class="l-line" data-line="1"><span class="l-x">x</div></span>))
    refute Output.valid?(~s(<pre class="lumis">))
  end
end
