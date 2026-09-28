defmodule HexpmWeb.API.ShortURLControllerTest do
  use HexpmWeb.ConnCase, async: true
  alias Hexpm.ShortURLs.{ShortURL, Target}

  setup do
    %{package: insert(:package)}
  end

  describe "post /api/short_url" do
    test "creates a short_code", %{package: package} do
      url = "https://diff.hex.pm/diffs?diffs[]=#{package.name}:3.0.0:3.0.1"

      assert %{"url" => short_url} =
               build_conn()
               |> post("/api/short_url", %{"url" => url})
               |> json_response(201)

      assert short_url =~ ~r/\/l\/[\w\d]{5}$/

      assert build_conn() |> get(URI.parse(short_url).path) |> redirected_to(301) ==
               "https://hex.pm/diffs?diffs[]=#{package.name}:3.0.0:3.0.1"
    end

    test "returns the existing short_code for the same comparisons", %{package: package} do
      first =
        build_conn()
        |> post("/api/short_url", %{
          "url" =>
            "https://diff.hex.pm/diffs?diffs[]=#{package.name}:3.0.0:3.0.1&diffs[]=#{package.name}:1.0.0:1.0.1"
        })
        |> json_response(201)

      second =
        build_conn()
        |> post("/api/short_url", %{
          "url" =>
            "https://hex.pm/diffs?diffs[]=#{package.name}:1.0.0:1.0.1&diffs[]=#{package.name}:3.0.0:3.0.1"
        })
        |> json_response(201)

      assert first == second
      assert Hexpm.Repo.aggregate(ShortURL, :count) == 1
      assert Hexpm.Repo.aggregate(Target, :count) == 1
    end

    test "fails given a url that is not a diff link" do
      assert %{"errors" => %{"url" => "must be a hex.pm diff link"}} =
               build_conn()
               |> post("/api/short_url", %{"url" => "https://hex.pm/packages/ecto"})
               |> json_response(422)
    end

    test "fails given only unknown packages" do
      assert %{"errors" => %{"url" => "must compare at least one package on hex.pm"}} =
               build_conn()
               |> post("/api/short_url", %{
                 "url" => "https://hex.pm/diffs?diffs[]=not_a_package:1.0.0:1.0.1"
               })
               |> json_response(422)
    end

    test "throttles new short urls per IP and still answers existing ones", %{package: package} do
      align_to_throttle_bucket()
      ip = {192, 0, 2, 12}
      existing = "https://hex.pm/diffs?diffs[]=#{package.name}:1.0.0:1.0.1"

      assert %{"url" => existing_short_url} = post_short_url(ip, existing) |> json_response(201)

      for patch <- 1..29 do
        url = "https://hex.pm/diffs?diffs[]=#{package.name}:2.0.#{patch}:3.0.0"
        assert post_short_url(ip, url) |> json_response(201)
        assert post_short_url(ip, existing) |> json_response(201)
      end

      conn = post_short_url(ip, "https://hex.pm/diffs?diffs[]=#{package.name}:4.0.0:5.0.0")
      assert %{"message" => "API rate limit exceeded for IP " <> _} = json_response(conn, 429)
      assert get_resp_header(conn, "x-ratelimit-limit") == ["30"]
      assert [_retry_after] = get_resp_header(conn, "retry-after")

      assert %{"url" => ^existing_short_url} = post_short_url(ip, existing) |> json_response(201)
      assert Hexpm.Repo.aggregate(ShortURL, :count) == 30

      other_ip = {192, 0, 2, 13}

      assert post_short_url(other_ip, "https://hex.pm/diffs?diffs[]=#{package.name}:4.0.0:5.0.0")
             |> json_response(201)
    end
  end

  defp post_short_url(ip, url) do
    build_conn()
    |> Map.put(:remote_ip, ip)
    |> post("/api/short_url", %{"url" => url})
  end

  defp align_to_throttle_bucket() do
    period = 10 * 60_000
    remaining = period - rem(System.system_time(:millisecond), period)
    if remaining < 10_000, do: Process.sleep(remaining + 50)
  end
end
