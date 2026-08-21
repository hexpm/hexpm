defmodule HexpmWeb.BlogControllerTest do
  use HexpmWeb.ConnCase, async: true

  test "renders a blog post" do
    document =
      build_conn()
      |> get("/blog/hex-v25-released")
      |> html_response(200)
      |> LazyHTML.from_document()

    assert LazyHTML.text(document["title"]) == "Hex v2.5 released | Hex"
  end
end
