defmodule HexpmWeb.InstallControllerTest do
  use HexpmWeb.ConnCase, async: true

  test "installs" do
    cdn_url = Application.get_env(:hexpm, :cdn_url)
    Application.put_env(:hexpm, :cdn_url, "http://s3.hex.pm")

    versions = [
      {"0.0.1", ["0.13.0-dev"]},
      {"0.1.0", ["0.13.1-dev"]},
      {"0.1.1", ["0.13.1-dev"]},
      {"0.1.2", ["0.13.1-dev"]},
      {"0.2.0", ["0.14.0", "0.14.1", "0.14.2"]},
      {"0.2.1", ["1.0.0"]}
    ]

    Enum.each(versions, fn {hex, elixirs} ->
      Hexpm.Repository.Install.build(hex, elixirs)
      |> Hexpm.Repo.insert()
    end)

    try do
      conn = get(build_conn(), "installs/hex.ez")
      assert redirected_to(conn) == "http://s3.hex.pm/installs/1.0.0/hex.ez"

      conn = get(build_conn(), "installs/hex.ez?elixir=0.0.1")
      assert redirected_to(conn) == "http://s3.hex.pm/installs/hex.ez"

      conn = get(build_conn(), "installs/hex.ez?elixir=0.13.0")
      assert redirected_to(conn) == "http://s3.hex.pm/installs/0.13.0-dev/hex.ez"

      conn = get(build_conn(), "installs/hex.ez?elixir=0.13.1")
      assert redirected_to(conn) == "http://s3.hex.pm/installs/0.13.1-dev/hex.ez"

      conn = get(build_conn(), "installs/hex.ez?elixir=0.14.0")
      assert redirected_to(conn) == "http://s3.hex.pm/installs/0.14.0/hex.ez"

      conn = get(build_conn(), "installs/hex.ez?elixir=0.14.1-dev")
      assert redirected_to(conn) == "http://s3.hex.pm/installs/0.14.0/hex.ez"

      conn = get(build_conn(), "installs/hex.ez?elixir=0.14.1")
      assert redirected_to(conn) == "http://s3.hex.pm/installs/0.14.1/hex.ez"

      conn = get(build_conn(), "installs/hex.ez?elixir=0.14.2")
      assert redirected_to(conn) == "http://s3.hex.pm/installs/0.14.2/hex.ez"

      conn =
        build_conn()
        |> put_req_header("user-agent", "Mix/0.14.1-dev")
        |> get("installs/hex.ez")

      assert redirected_to(conn) == "http://s3.hex.pm/installs/0.14.0/hex.ez"
    after
      Application.put_env(:hexpm, :cdn_url, cdn_url)
    end
  end
end
