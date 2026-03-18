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

  defp mock_file_list_and_readme(package_name, version, filename, content) do
    file_list = Jason.encode!([filename])

    Mox.expect(Hexpm.HTTP.Mock, :get, 2, fn url, _headers ->
      cond do
        String.contains?(url, "/preview-files/#{package_name}-#{version}.json") ->
          {:ok, 200, [], file_list}

        String.ends_with?(url, "/#{filename}") ->
          {:ok, 200, [], content}

        true ->
          {:ok, 404, [], ""}
      end
    end)
  end

  defp mock_file_list(package_name, version, files) do
    file_list = Jason.encode!(files)

    Mox.expect(Hexpm.HTTP.Mock, :get, fn url, _headers ->
      if String.contains?(url, "/preview-files/#{package_name}-#{version}.json") do
        {:ok, 200, [], file_list}
      else
        {:ok, 404, [], ""}
      end
    end)
  end

  defp mock_no_file_list do
    Mox.expect(Hexpm.HTTP.Mock, :get, fn _url, _headers ->
      {:ok, 404, [], ""}
    end)
  end

  describe "show/2" do
    test "renders README for package with version", %{package: package} do
      mock_file_list_and_readme(
        package.name,
        "1.0.0",
        "README.md",
        "# My Package\n\nThis is a test README."
      )

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      assert conn.status == 200
      assert conn.resp_body =~ "My Package"
      assert conn.resp_body =~ "This is a test README."
      assert get_resp_header(conn, "content-security-policy") |> List.first() =~ "frame-ancestors"
      assert get_resp_header(conn, "cache-control") == ["public, max-age=86400"]
    end

    test "redirects versionless URL to latest version", %{package: package} do
      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}")

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/#{package.name}/1.0.0"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=3600"]
    end

    test "renders plain text for non-markdown README", %{package: package} do
      mock_file_list_and_readme(
        package.name,
        "1.0.0",
        "README",
        "Plain text README content"
      )

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      assert conn.status == 200
      assert conn.resp_body =~ "<pre>"
      assert conn.resp_body =~ "Plain text README content"
    end

    test "renders plain text for .txt README", %{package: package} do
      mock_file_list_and_readme(package.name, "1.0.0", "README.txt", "Text README")

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      assert conn.status == 200
      assert conn.resp_body =~ "<pre>"
      assert conn.resp_body =~ "Text README"
    end

    test "shows no README when file list has no readme files", %{package: package} do
      mock_file_list(package.name, "1.0.0", ["lib/my_package.ex", "mix.exs"])

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      assert conn.status == 200
      assert conn.resp_body =~ "readme-not-found"
    end

    test "shows no README when no file list exists", %{package: package} do
      mock_no_file_list()

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
      mock_file_list_and_readme(
        package.name,
        "1.0.0",
        "README.md",
        "# Title\n\n<script>alert(1)</script>\n\nSafe content."
      )

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      assert conn.status == 200
      refute conn.resp_body =~ "<script>alert"
      assert conn.resp_body =~ "Safe content."
    end

    test "sets correct CSP headers", %{package: package} do
      mock_file_list_and_readme(package.name, "1.0.0", "README.md", "# Test")

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

    test "syntax highlights elixir code blocks", %{package: package} do
      mock_file_list_and_readme(
        package.name,
        "1.0.0",
        "README.md",
        "```elixir\nIO.puts(\"hello\")\n```"
      )

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      assert conn.status == 200
      # Makeup wraps tokens in spans with class attributes
      assert conn.resp_body =~ "<span class=\""
      # The code content should be present
      assert conn.resp_body =~ "IO"
      assert conn.resp_body =~ "puts"
    end

    test "preserves newlines in unhighlighted code blocks", %{package: package} do
      mock_file_list_and_readme(
        package.name,
        "1.0.0",
        "README.md",
        "```\nfoo\nbar\nbaz\n```"
      )

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      assert conn.status == 200
      assert conn.resp_body =~ "foo\nbar\nbaz"
    end

    test "preserves newlines in highlighted code blocks", %{package: package} do
      mock_file_list_and_readme(
        package.name,
        "1.0.0",
        "README.md",
        "```elixir\nfoo\nbar\nbaz\n```"
      )

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      assert conn.status == 200
      # Makeup wraps whitespace in spans, newlines must be preserved
      assert conn.resp_body =~ "foo"
      assert conn.resp_body =~ "bar"
      assert conn.resp_body =~ "baz"
      assert conn.resp_body =~ "\n"
    end

    test "rewrites image URLs to proxy", %{package: package} do
      mock_file_list_and_readme(
        package.name,
        "1.0.0",
        "README.md",
        "![logo](https://example.com/logo.png)"
      )

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
