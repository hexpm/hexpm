defmodule HexWeb.RouterTest do
  use HexWebTest.Case
  import Plug.Conn
  import Plug.Test
  alias HexWeb.Router
  alias HexWeb.User
  alias HexWeb.Package
  alias HexWeb.Release
  alias HexWeb.RegistryBuilder

  setup do
    User.create("other", "other@mail.com", "other", true)
    {:ok, user} = User.create("eric", "eric@mail.com", "eric", true)
    {:ok, _}    = Package.create("postgrex", user, %{})
    {:ok, pkg}  = Package.create("decimal", user, %{})
    {:ok, _}    = Release.create(pkg, "0.0.1", "decimal", [{"postgrex", "0.0.1"}], "")
    :ok
  end

  test "fetch registry" do
    RegistryBuilder.rebuild

    conn = conn("GET", "/registry.ets.gz")
    conn = Router.call(conn, [])

    assert conn.status in 200..399
  end

  @tag :integration
  test "integration fetch registry" do
    if Application.get_env(:hex_web, :s3_bucket) do
      Application.put_env(:hex_web, :store, HexWeb.Store.S3)
    end

    RegistryBuilder.rebuild

    url = HexWeb.Util.cdn_url("registry.ets.gz") |> String.to_char_list
    :inets.start

    assert {:ok, response} = :httpc.request(:head, {url, []}, [], [])
    assert {{_version, 200, _reason}, _headers, _body} = response
  after
    Application.put_env(:hex_web, :store, HexWeb.Store.Local)
  end

  @tag :integration
  test "integration fetch tarball" do
    if Application.get_env(:hex_web, :s3_bucket) do
      Application.put_env(:hex_web, :store, HexWeb.Store.S3)
    end

    headers = [ {"content-type", "application/octet-stream"},
                {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    body = create_tar(%{name: :postgrex, version: "0.0.1", requirements: %{decimal: "~> 0.0.1"}}, [])
    conn = conn("POST", "/api/packages/postgrex/releases", body, headers: headers)
    conn = Router.call(conn, [])
    assert conn.status == 201

    port = Application.get_env(:hex_web, :port)
    url = String.to_char_list("http://localhost:#{port}/tarballs/postgrex-0.0.1.tar")
    :inets.start

    assert {:ok, response} = :httpc.request(:head, {url, []}, [], [])
    assert {{_version, 200, _reason}, _headers, _body} = response
  after
    Application.put_env(:hex_web, :store, HexWeb.Store.Local)
  end

  test "redirect" do
    url      = Application.get_env(:hex_web, :url)
    use_ssl  = Application.get_env(:hex_web, :use_ssl)

    Application.put_env(:hex_web, :url, "https://hex.pm")
    Application.put_env(:hex_web, :use_ssl, true)

    try do
      conn = %{conn("GET", "/foobar") | scheme: :http}
      conn = Router.call(conn, [])
      assert conn.status == 301
      assert get_resp_header(conn, "location") == ["https://hex.pm/foobar"]
    after
      Application.put_env(:hex_web, :url, url)
      Application.put_env(:hex_web, :use_ssl, use_ssl)
    end
  end

  test "forwarded" do
    headers = [{"x-forwarded-proto", "https"}]
    conn = conn("GET", "/installs/hex.ez", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.scheme == :https

    headers = [{"x-forwarded-for", "1.2.3.4"}]
    conn = conn("GET", "/installs/hex.ez", nil, headers: headers)
    conn = Router.call(conn, [])
    assert conn.remote_ip == {1,2,3,4}
  end

  test "installs" do
    cdn_url = Application.get_env(:hex_web, :cdn_url)
    Application.put_env(:hex_web, :cdn_url, "http://s3.hex.pm")

    versions = [{"0.0.1", ["0.13.0-dev"]}, {"0.1.0", ["0.13.1-dev"]},
                {"0.1.1", ["0.13.1-dev"]}, {"0.1.2", ["0.13.1-dev"]},
                {"0.2.0", ["0.14.0", "0.14.1", "0.14.2"]},
                {"0.2.1", ["1.0.0"]}]

    Enum.each(versions, fn {hex, elixirs} -> HexWeb.Install.create(hex, elixirs) end)

    try do
      conn = conn("GET", "/installs/hex.ez")
      conn = Router.call(conn, [])
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://s3.hex.pm/installs/1.0.0/hex.ez"]

      conn = conn("GET", "/installs/hex.ez?elixir=0.0.1")
      conn = Router.call(conn, [])
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://s3.hex.pm/installs/hex.ez"]

      conn = conn("GET", "/installs/hex.ez?elixir=0.13.0")
      conn = Router.call(conn, [])
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://s3.hex.pm/installs/0.13.0-dev/hex.ez"]

      conn = conn("GET", "/installs/hex.ez?elixir=0.13.1")
      conn = Router.call(conn, [])
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://s3.hex.pm/installs/0.13.1-dev/hex.ez"]

      conn = conn("GET", "/installs/hex.ez?elixir=0.14.0")
      conn = Router.call(conn, [])
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://s3.hex.pm/installs/0.14.0/hex.ez"]

      conn = conn("GET", "/installs/hex.ez?elixir=0.14.1-dev")
      conn = Router.call(conn, [])
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://s3.hex.pm/installs/0.14.0/hex.ez"]

      conn = conn("GET", "/installs/hex.ez?elixir=0.14.1")
      conn = Router.call(conn, [])
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://s3.hex.pm/installs/0.14.1/hex.ez"]

      conn = conn("GET", "/installs/hex.ez?elixir=0.14.2")
      conn = Router.call(conn, [])
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://s3.hex.pm/installs/0.14.2/hex.ez"]

      headers = [ {"user-agent", "Mix/0.14.1-dev"} ]
      conn = conn("GET", "/installs/hex.ez", nil, headers: headers)
      conn = Router.call(conn, [])
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://s3.hex.pm/installs/0.14.0/hex.ez"]
    after
      Application.put_env(:hex_web, :cdn_url, cdn_url)
    end
  end

  test "blocked address" do
    conn = conn("GET", "/")
    conn = Router.call(conn, [])
    assert conn.status == 200

    %HexWeb.BlockedAddress{ip: "1.2.3.4"}
    |> HexWeb.Repo.insert

    HexWeb.BlockedAddress.reload

    conn = conn("GET", "/")
    conn = %{conn | remote_ip: {1,2,3,4}}
    conn = Router.call(conn, [])
    assert conn.status == 401
  end
end
