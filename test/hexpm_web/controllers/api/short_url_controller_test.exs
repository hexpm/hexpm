defmodule HexpmWeb.API.ShortURLControllerTest do
  use HexpmWeb.ConnCase, async: true

  describe "post /api/short_url" do
    test "creates a short_code" do
      assert %{"url" => url} =
               build_conn()
               |> post("api/short_url", %{"url" => "https://diff.hex.pm?diff[]=ecto:3.0.0:3.0.1"})
               |> json_response(201)

      assert url =~ ~r/\/l\/[\w\d]{5}/
    end

    test "fails given an invalid url" do
      assert build_conn()
             |> post("api/short_url", %{"url" => "https://aol.com"})
             |> response(422)
    end
  end
end
