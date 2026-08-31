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
    Hexpm.Store.put(
      :preview_bucket,
      "file_lists/#{package_name}-#{version}.json",
      JSON.encode!([filename])
    )

    Hexpm.Store.put(:preview_bucket, "files/#{package_name}/#{version}/#{filename}", content)
  end

  defp mock_file_list(package_name, version, files) do
    Hexpm.Store.put(
      :preview_bucket,
      "file_lists/#{package_name}-#{version}.json",
      JSON.encode!(files)
    )
  end

  describe "show/2 for private packages" do
    setup do
      repository = insert(:repository)
      package = insert(:package, repository_id: repository.id, name: "private_readme")

      insert(
        :release,
        package: package,
        version: "1.0.0",
        meta: build(:release_metadata, app: package.name)
      )

      Hexpm.Store.put(
        :preview_bucket,
        "repos/#{repository.name}/file_lists/#{package.name}-1.0.0.json",
        JSON.encode!(["README.md"])
      )

      Hexpm.Store.put(
        :preview_bucket,
        "repos/#{repository.name}/files/#{package.name}/1.0.0/README.md",
        "# Private Package"
      )

      %{repository: repository, private_package: package}
    end

    test "renders README with a valid token", %{
      repository: repository,
      private_package: package
    } do
      token = HexpmWeb.ReadmeToken.sign(repository.name, package.name, "1.0.0")

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{repository.name}/#{package.name}/1.0.0?token=#{token}")

      assert conn.status == 200
      assert conn.resp_body =~ "Private Package"
      assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    end

    test "shows no README for missing, mismatched, or expired tokens", %{
      repository: repository,
      private_package: package
    } do
      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{repository.name}/#{package.name}/1.0.0")

      assert conn.status == 404

      other_token = HexpmWeb.ReadmeToken.sign(repository.name, "other_package", "1.0.0")

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{repository.name}/#{package.name}/1.0.0?token=#{other_token}")

      assert conn.status == 200
      assert conn.resp_body =~ "readme-not-found"
      assert get_resp_header(conn, "cache-control") == ["private, no-store"]

      version_token = HexpmWeb.ReadmeToken.sign(repository.name, package.name, "2.0.0")

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{repository.name}/#{package.name}/1.0.0?token=#{version_token}")

      assert conn.resp_body =~ "readme-not-found"
    end
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

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/nonexistent_package")

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
      # Code Highlighter wraps tokens in spans with class attributes
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
      assert conn.resp_body =~ ~s|class="l-constant">&#39;div&#39;|
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
      # The lines must stay on separate lines; a collapsed block would not
      # match the newline-separated pattern.
      assert conn.resp_body =~ ~r/foo.*\n.*bar.*\n.*baz/
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
      # The lines must stay on separate lines even when wrapped in
      # highlighting markup; a collapsed block would not match.
      assert conn.resp_body =~ ~r/foo.*\n.*bar.*\n.*baz/
    end

    test "consumes inline attribute list markers after tables", %{package: package} do
      mock_file_list_and_readme(
        package.name,
        "1.0.0",
        "README.md",
        "| a | b |\n|---|---|\n| 1 | 2 |\n{: .my-class}\n"
      )

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      assert conn.status == 200
      assert conn.resp_body =~ "<table"
      # The marker is stripped, not rendered as a literal table row.
      refute conn.resp_body =~ "{:"
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
      assert conn.resp_body =~ ~s[<input type="checkbox" disabled=""/>]
      assert conn.resp_body =~ ~s[<input type="checkbox" checked="" disabled=""/>]
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

  describe "show/2 with a kind" do
    test "renders a recognized doc kind", %{package: package} do
      mock_file_list_and_readme(
        package.name,
        "1.0.0",
        "CHANGELOG.md",
        "# Changelog\n\nv1.0.0 notes"
      )

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0?kind=changelog")

      assert conn.status == 200
      assert conn.resp_body =~ "Changelog"
      assert conn.resp_body =~ "v1.0.0 notes"
      assert get_resp_header(conn, "cache-control") == ["public, max-age=86400"]
    end

    test "renders the not-found page when the requested kind is missing", %{package: package} do
      mock_file_list(package.name, "1.0.0", ["README.md"])

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0?kind=changelog")

      assert conn.status == 200
      assert conn.resp_body =~ "readme-not-found"
    end

    test "404s for an unrecognized kind", %{package: package} do
      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0?kind=bogus")

      assert conn.status == 404
    end

    test "preserves the kind through the versionless redirect", %{package: package} do
      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}?kind=changelog")

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/#{package.name}/1.0.0?kind=changelog"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=3600"]
    end

    test "404s the versionless route for an unrecognized kind", %{package: package} do
      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}?kind=bogus")

      assert conn.status == 404
    end

    test "no kind param behaves exactly like :readme (back-compat)", %{package: package} do
      mock_file_list_and_readme(package.name, "1.0.0", "README.md", "# Hi")

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{package.name}/1.0.0")

      assert conn.status == 200
      assert conn.resp_body =~ "Hi"
    end
  end

  describe "show/2 for private packages with a kind" do
    setup do
      repository = insert(:repository)
      package = insert(:package, repository_id: repository.id, name: "private_docs")

      insert(
        :release,
        package: package,
        version: "1.0.0",
        meta: build(:release_metadata, app: package.name)
      )

      Hexpm.Store.put(
        :preview_bucket,
        "repos/#{repository.name}/file_lists/#{package.name}-1.0.0.json",
        JSON.encode!(["README.md", "SECURITY.md"])
      )

      Hexpm.Store.put(
        :preview_bucket,
        "repos/#{repository.name}/files/#{package.name}/1.0.0/SECURITY.md",
        "# Report a vulnerability"
      )

      %{repository: repository, private_package: package}
    end

    test "renders a recognized kind with a valid token", %{
      repository: repository,
      private_package: package
    } do
      token = HexpmWeb.ReadmeToken.sign(repository.name, package.name, "1.0.0")

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{repository.name}/#{package.name}/1.0.0?token=#{token}&kind=security")

      assert conn.status == 200
      assert conn.resp_body =~ "Report a vulnerability"
      assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    end

    test "404s for an unrecognized kind even with a valid token", %{
      repository: repository,
      private_package: package
    } do
      token = HexpmWeb.ReadmeToken.sign(repository.name, package.name, "1.0.0")

      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{repository.name}/#{package.name}/1.0.0?token=#{token}&kind=bogus")

      assert conn.status == 404
    end

    test "repository-scoped URL with no token at all 404s regardless of kind", %{
      repository: repository,
      private_package: package
    } do
      conn =
        build_conn()
        |> Map.put(:host, "readme.localhost")
        |> get("/#{repository.name}/#{package.name}/1.0.0?kind=security")

      assert conn.status == 404
    end
  end
end
