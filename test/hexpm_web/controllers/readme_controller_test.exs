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

    Mox.expect(Hexpm.HTTP.Mock, :get, fn url, _headers ->
      if String.contains?(url, "/preview-files/#{package_name}-#{version}.json") do
        {:ok, 200, [], file_list}
      else
        {:ok, 404, [], ""}
      end
    end)

    Mox.expect(Hexpm.HTTP.Mock, :get, fn url, _headers, _opts ->
      if String.ends_with?(url, "/#{filename}") do
        {:ok, 200, [], content}
      else
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

  defp mock_files_and_content(package_name, version, files, filename, content) do
    file_list = Jason.encode!(files)

    Mox.expect(Hexpm.HTTP.Mock, :get, fn url, _headers ->
      if String.contains?(url, "/preview-files/#{package_name}-#{version}.json") do
        {:ok, 200, [], file_list}
      else
        {:ok, 404, [], ""}
      end
    end)

    Mox.expect(Hexpm.HTTP.Mock, :get, fn url, _headers, _opts ->
      if String.ends_with?(url, "/#{filename}") do
        {:ok, 200, [], content}
      else
        {:ok, 404, [], ""}
      end
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

    test "decodes single quotes in highlighted code blocks", %{package: package} do
      mock_file_list_and_readme(
        package.name,
        "1.0.0",
        "README.md",
        "```erlang\n{'div', []}.\n```"
      )

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      assert conn.status == 200
      assert conn.resp_body =~ ~s|class="ss">&#39;div&#39;|
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

    test "renders task list checkboxes", %{package: package} do
      mock_file_list_and_readme(
        package.name,
        "1.0.0",
        "README.md",
        "- [ ] unchecked\n- [x] checked\n- normal\n"
      )

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      assert conn.status == 200
      assert conn.resp_body =~ ~s[<input type="checkbox" disabled="disabled"/>]
      assert conn.resp_body =~ ~s[<input type="checkbox" checked="checked" disabled="disabled"/>]
      assert conn.resp_body =~ "unchecked"
      assert conn.resp_body =~ "checked"
      assert conn.resp_body =~ "normal"
    end

    test "renders markdown with parse warnings", %{package: package} do
      mock_file_list_and_readme(
        package.name,
        "1.0.0",
        "README.md",
        "# Title\n\nSome `unclosed backtick"
      )

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      assert conn.status == 200
      assert conn.resp_body =~ "Title"
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

  describe "show_doc/2" do
    test "renders a markdown changelog", %{package: package} do
      mock_files_and_content(
        package.name,
        "1.0.0",
        ["README.md", "CHANGELOG.md"],
        "CHANGELOG.md",
        "# Changelog\n\n## v1.0.0\n\n- First release"
      )

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0/changelog")

      assert conn.status == 200
      assert conn.resp_body =~ "First release"
      assert conn.resp_body =~ ~s("doc-files")
      assert conn.resp_body =~ ~s(["readme","changelog"])
      assert conn.resp_body =~ "CHANGELOG.md"
      assert get_resp_header(conn, "cache-control") == ["public, max-age=86400"]
    end

    test "renders a bare LICENSE file as escaped pre", %{package: package} do
      mock_files_and_content(
        package.name,
        "1.0.0",
        ["README.md", "LICENSE"],
        "LICENSE",
        "Apache License <2.0>"
      )

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0/license")

      assert conn.status == 200
      assert conn.resp_body =~ "Apache License &lt;2.0&gt;"
    end

    test "missing kind renders not-found page that still reports doc-files", %{package: package} do
      mock_file_list(package.name, "1.0.0", ["README.md", "CHANGELOG.md"])

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0/security")

      assert conn.status == 200
      assert conn.resp_body =~ "readme-not-found"
      assert conn.resp_body =~ ~s(["readme","changelog"])
      assert get_resp_header(conn, "cache-control") == ["public, max-age=3600"]
    end

    test "unknown kind segment is a 404", %{package: package} do
      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0/contributing")

      assert conn.status == 404
    end

    test "versionless doc URL redirects to latest version", %{package: package} do
      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/changelog")

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/#{package.name}/1.0.0/changelog"]
    end

    test "oversized file renders a too-large notice", %{package: package} do
      big = String.duplicate("a", 2 * 1024 * 1024 + 1)
      mock_files_and_content(package.name, "1.0.0", ["CHANGELOG.md"], "CHANGELOG.md", big)

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0/changelog")

      assert conn.status == 200
      assert conn.resp_body =~ "too large to display"
      assert conn.resp_body =~ "CHANGELOG.md"
      assert conn.resp_body =~ Hexpm.Utils.preview_html_url(package.name, "1.0.0")
      refute conn.resp_body =~ "aaaaaaaaaa"
    end

    test "document fetch aborted for exceeding max body size renders a too-large notice", %{
      package: package
    } do
      file_list = Jason.encode!(["CHANGELOG.md"])

      Mox.expect(Hexpm.HTTP.Mock, :get, fn url, _headers ->
        if String.contains?(url, "/preview-files/#{package.name}-1.0.0.json") do
          {:ok, 200, [], file_list}
        else
          {:ok, 404, [], ""}
        end
      end)

      Mox.expect(Hexpm.HTTP.Mock, :get, fn _url, _headers, _opts ->
        {:error, :body_too_large}
      end)

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0/changelog")

      assert conn.status == 200
      assert conn.resp_body =~ "too large to display"
      assert conn.resp_body =~ "CHANGELOG.md"
    end

    test "upstream failure fetching file list is not cached", %{package: package} do
      Mox.expect(Hexpm.HTTP.Mock, :get, fn _url, _headers ->
        {:ok, 502, [], ""}
      end)

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0/changelog")

      assert conn.status == 200
      assert conn.resp_body =~ "readme-not-found"
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    test "connection error fetching file list is not cached", %{package: package} do
      Mox.expect(Hexpm.HTTP.Mock, :get, fn _url, _headers ->
        {:error, :timeout}
      end)

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0/changelog")

      assert conn.status == 200
      assert conn.resp_body =~ "readme-not-found"
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    test "upstream failure fetching document is not cached", %{package: package} do
      file_list = Jason.encode!(["CHANGELOG.md"])

      Mox.expect(Hexpm.HTTP.Mock, :get, fn url, _headers ->
        if String.contains?(url, "/preview-files/#{package.name}-1.0.0.json") do
          {:ok, 200, [], file_list}
        else
          {:ok, 404, [], ""}
        end
      end)

      Mox.expect(Hexpm.HTTP.Mock, :get, fn _url, _headers, _opts ->
        {:ok, 503, [], ""}
      end)

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0/changelog")

      assert conn.status == 200
      assert conn.resp_body =~ "readme-not-found"
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    test "genuinely missing file is still cached", %{package: package} do
      mock_file_list(package.name, "1.0.0", ["README.md"])

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0/changelog")

      assert conn.status == 200
      assert conn.resp_body =~ "readme-not-found"
      assert get_resp_header(conn, "cache-control") == ["public, max-age=3600"]
    end

    test "non-list JSON file list degrades to not-found without crashing", %{package: package} do
      Mox.expect(Hexpm.HTTP.Mock, :get, fn url, _headers ->
        if String.contains?(url, "/preview-files/#{package.name}-1.0.0.json") do
          {:ok, 200, [], Jason.encode!(%{"not" => "a list"})}
        else
          {:ok, 404, [], ""}
        end
      end)

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0/changelog")

      assert conn.status == 200
      assert conn.resp_body =~ "readme-not-found"
    end

    test "already-decoded (non-binary) JSON file list body is tolerated", %{package: package} do
      Mox.expect(Hexpm.HTTP.Mock, :get, fn url, _headers ->
        if String.contains?(url, "/preview-files/#{package.name}-1.0.0.json") do
          {:ok, 200, [{"content-type", "application/json"}], ["CHANGELOG.md"]}
        else
          {:ok, 404, [], ""}
        end
      end)

      Mox.expect(Hexpm.HTTP.Mock, :get, fn _url, _headers, _opts ->
        {:ok, 200, [], "# Changelog"}
      end)

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0/changelog")

      assert conn.status == 200
      assert conn.resp_body =~ "Changelog"
    end

    test "invalid JSON file list degrades to not-found without a 500", %{package: package} do
      Mox.expect(Hexpm.HTTP.Mock, :get, fn url, _headers ->
        if String.contains?(url, "/preview-files/#{package.name}-1.0.0.json") do
          {:ok, 200, [], "not json {{{"}
        else
          {:ok, 404, [], ""}
        end
      end)

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0/changelog")

      assert conn.status == 200
      assert conn.resp_body =~ "readme-not-found"
    end

    test "readme show page also reports doc-files", %{package: package} do
      mock_files_and_content(
        package.name,
        "1.0.0",
        ["README.md", "LICENSE"],
        "README.md",
        "# Hello"
      )

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      assert conn.status == 200
      assert conn.resp_body =~ ~s(["readme","license"])
      assert conn.resp_body =~ ~s("README.md")
    end
  end
end
