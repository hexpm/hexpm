defmodule HexpmWeb.ReadmeControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    package = insert(:package, name: "my_package")

    insert(
      :release,
      package: package,
      version: "1.0.0",
      meta: build(:release_metadata, app: package.name)
    )

    %{package: package}
  end

  defp mock_readme(filename, content) do
    Mox.expect(Hexpm.HTTP.Mock, :get, fn url, _headers ->
      if String.ends_with?(url, "/#{filename}") do
        {:ok, 200, [], content}
      else
        {:ok, 404, [], ""}
      end
    end)
  end

  defp mock_readme_not_found do
    Mox.expect(Hexpm.HTTP.Mock, :get, 8, fn _url, _headers ->
      {:ok, 404, [], ""}
    end)
  end

  describe "show/2" do
    test "renders README for package with version", %{package: package} do
      mock_readme("README.md", "# My Package\n\nThis is a test README.")

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      assert conn.status == 200
      assert conn.resp_body =~ "My Package"
      assert conn.resp_body =~ "This is a test README."
      assert get_resp_header(conn, "content-security-policy") |> List.first() =~ "frame-ancestors"
      assert get_resp_header(conn, "cache-control") == ["public, max-age=3600"]
    end

    test "renders README for package without version (latest)", %{package: package} do
      mock_readme("README.md", "# Latest README")

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}")

      assert conn.status == 200
      assert conn.resp_body =~ "Latest README"
    end

    test "tries lowercase readme.md", %{package: package} do
      # First try README.md (404), then readme.md (200)
      Mox.expect(Hexpm.HTTP.Mock, :get, 2, fn url, _headers ->
        if String.ends_with?(url, "/readme.md") do
          {:ok, 200, [], "# Lowercase Readme"}
        else
          {:ok, 404, [], ""}
        end
      end)

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      assert conn.status == 200
      assert conn.resp_body =~ "Lowercase Readme"
    end

    test "renders plain text for non-markdown README", %{package: package} do
      # All markdown variants return 404, then txt variants, then README without extension
      Mox.expect(Hexpm.HTTP.Mock, :get, 7, fn url, _headers ->
        if String.ends_with?(url, "/README") do
          {:ok, 200, [], "Plain text README content"}
        else
          {:ok, 404, [], ""}
        end
      end)

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      assert conn.status == 200
      assert conn.resp_body =~ "<pre>"
      assert conn.resp_body =~ "Plain text README content"
    end

    test "renders plain text for .txt README", %{package: package} do
      # All md/markdown variants return 404, then README.txt matches
      Mox.expect(Hexpm.HTTP.Mock, :get, 5, fn url, _headers ->
        if String.ends_with?(url, "/README.txt") do
          {:ok, 200, [], "Text README"}
        else
          {:ok, 404, [], ""}
        end
      end)

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      assert conn.status == 200
      assert conn.resp_body =~ "<pre>"
      assert conn.resp_body =~ "Text README"
    end

    test "shows no README when all filenames return 404", %{package: package} do
      mock_readme_not_found()

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      assert conn.status == 200
      assert conn.resp_body =~ "readme-not-found"
    end

    test "shows no README for nonexistent package" do
      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/nonexistent_package/1.0.0")

      assert conn.status == 200
      assert conn.resp_body =~ "readme-not-found"
    end

    test "shows no README for nonexistent version", %{package: package} do
      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/99.99.99")

      assert conn.status == 200
      assert conn.resp_body =~ "readme-not-found"
    end

    test "returns 404 for non-readme paths on readme host" do
      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/dashboard/security/change-password")

      assert conn.status == 404
    end

    test "returns 404 for root path on readme host" do
      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/")

      assert conn.status == 404
    end

    test "sanitizes HTML in README", %{package: package} do
      mock_readme("README.md", "# Title\n\n<script>alert(1)</script>\n\nSafe content.")

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      assert conn.status == 200
      refute conn.resp_body =~ "<script>alert"
      assert conn.resp_body =~ "Safe content."
    end

    test "sets correct CSP headers", %{package: package} do
      mock_readme("README.md", "# Test")

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ "default-src 'none'"
      assert csp =~ "script-src 'nonce-"
      assert csp =~ "style-src 'nonce-"
      assert csp =~ "img-src"
      assert csp =~ "frame-ancestors"
    end

    test "rewrites image URLs to proxy", %{package: package} do
      mock_readme("README.md", "![logo](https://example.com/logo.png)")

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      assert conn.status == 200
      assert conn.resp_body =~ "http://localhost:5000/img/fetch/"
      refute conn.resp_body =~ ~s[src="https://example.com/logo.png"]
    end
  end
end
