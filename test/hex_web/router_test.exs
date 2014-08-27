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
    User.create("other", "other@mail.com", "other")
    {:ok, user} = User.create("eric", "eric@mail.com", "eric")
    {:ok, _}    = Package.create("postgrex", user, %{})
    {:ok, pkg}  = Package.create("decimal", user, %{})
    {:ok, _}    = Release.create(pkg, "0.0.1", [{"postgrex", "0.0.1"}], "")
    :ok
  end

  test "fetch registry" do
    {:ok, _} = RegistryBuilder.start_link
    RegistryBuilder.sync_rebuild

    conn = conn("GET", "/registry.ets.gz")
    conn = Router.call(conn, [])

    assert conn.status in 200..399
  after
    RegistryBuilder.stop
  end

  @tag :integration
  test "integration fetch registry" do
    if Application.get_env(:hex_web, :s3_bucket) do
      Application.put_env(:hex_web, :store, HexWeb.Store.S3)
    end

    {:ok, _} = RegistryBuilder.start_link
    RegistryBuilder.sync_rebuild

    port = Application.get_env(:hex_web, :port)
    url = String.to_char_list("http://localhost:#{port}/registry.ets.gz")
    :inets.start

    assert {:ok, response} = :httpc.request(:head, {url, []}, [], [])
    assert {{_version, 200, _reason}, _headers, _body} = response
  after
    RegistryBuilder.stop
    Application.put_env(:hex_web, :store, HexWeb.Store.Local)
  end

  @tag :integration
  test "integration fetch tarball" do
    if Application.get_env(:hex_web, :s3_bucket) do
      Application.get_env(:hex_web, :store, HexWeb.Store.S3)
    end

    headers = [ {"content-type", "application/octet-stream"},
                {"authorization", "Basic " <> :base64.encode("eric:eric")}]
    body = create_tar(%{app: :postgrex, version: "0.0.1", requirements: %{decimal: "~> 0.0.1"}}, [])
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
    app_host = Application.get_env(:hex_web, :app_host)
    use_ssl  = Application.get_env(:hex_web, :use_ssl)

    Application.put_env(:hex_web, :url, "https://hex.pm")
    Application.put_env(:hex_web, :app_host, "some-host.com")
    Application.put_env(:hex_web, :use_ssl, true)

    try do
      conn = %{conn("GET", "/foobar") | scheme: :http}
      conn = Router.call(conn, [])
      assert conn.status == 301
      assert get_resp_header(conn, "location") == ["https://hex.pm/foobar"]

      conn = %{conn("GET", "/foobar") | scheme: :https, host: "some-host.com"}
      conn = Router.call(conn, [])
      assert conn.status == 301
      assert get_resp_header(conn, "location") == ["https://hex.pm/foobar"]
    after
      Application.put_env(:hex_web, :url, url)
      Application.put_env(:hex_web, :app_host, app_host)
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
    assert conn.port == 12345
  end

  test "installs" do
    cdn_url = Application.get_env(:hex_web, :cdn_url)
    Application.put_env(:hex_web, :cdn_url, "http://s3.hex.pm")

    versions = [{"0.0.1", "0.13.0-dev"}, {"0.1.0", "0.13.1-dev"},
                {"0.1.1", "0.13.1-dev"}, {"0.1.2", "0.13.1-dev"}]

    Enum.each(versions, fn {hex, elixir} -> HexWeb.Install.create(hex, elixir) end)

    try do
      conn = conn("GET", "/installs/hex.ez")
      conn = Router.call(conn, [])
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://s3.hex.pm/installs/hex.ez"]

      headers = [ {"user-agent", "Mix/0.0.1"} ]
      conn = conn("GET", "/installs/hex.ez", nil, headers: headers)
      conn = Router.call(conn, [])
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://s3.hex.pm/installs/hex.ez"]

      headers = [ {"user-agent", "Mix/0.13.0"} ]
      conn = conn("GET", "/installs/hex.ez", nil, headers: headers)
      conn = Router.call(conn, [])
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://s3.hex.pm/installs/0.0.1/hex.ez"]

      headers = [ {"user-agent", "Mix/0.13.1"} ]
      conn = conn("GET", "/installs/hex.ez", nil, headers: headers)
      conn = Router.call(conn, [])
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://s3.hex.pm/installs/0.1.2/hex.ez"]
    after
      Application.put_env(:hex_web, :cdn_url, cdn_url)
    end
  end
end
