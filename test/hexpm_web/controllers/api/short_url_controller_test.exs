defmodule HexpmWeb.API.ShortURLControllerTest do
  use HexpmWeb.ConnCase, async: true

  describe "post /api/short_url" do
    test "creates a short_code" do
      assert build_conn()
             |> post("api/short_url", %{"url" => "https://diff.hex.pm?diff[]=ecto:3.0.0:3.0.1"})
             |> response(201)
    end

    test "fails given an invalid url" do
      assert build_conn()
             |> post("api/short_url", %{"url" => "https://aol.com"})
             |> response(422)
    end
  end
end
