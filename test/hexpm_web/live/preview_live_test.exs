defmodule HexpmWeb.PreviewLiveTest do
  use HexpmWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup do
    %{conn: build_conn()}
  end

  # <template> content is a separate fragment, so selectors do not descend into
  # it and it has to be read out of the markup.
  defp template_html(html, name) do
    [_, inner] = Regex.run(~r|<template data-#{name}[^>]*>(.*?)</template>|s, html)
    inner
  end

  # The payload holds route-ready paths, so it is decoded back to names here to
  # keep assertions readable.
  defp file_paths(html) do
    html
    |> template_html("file-paths")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&amp;", "&")
    |> JSON.decode!()
    |> Enum.map(&URI.decode/1)
  end

  test "renders package files inside the package layout", %{conn: conn} do
    put_release("live_preview", "1.0.0", [
      {"README.md", "readme"},
      {"lib/live_preview.ex", "defmodule LivePreview do\nend\n"}
    ])

    {:ok, view, html} =
      live(conn, "/packages/live_preview/1.0.0/files/lib/live_preview.ex")

    assert html =~ "live_preview"
    assert html =~ "1.0.0"
    assert html =~ "LineHighlight"
    assert html =~ "l-line"
    assert page_title(view) == "lib/live_preview.ex - live_preview 1.0.0 | Hex"
    assert has_element?(view, ~s(a[data-path="lib/live_preview.ex"]), "live_preview.ex")

    assert has_element?(
             view,
             ~s(aside[phx-hook="FileFinder"][data-active-path="lib/live_preview.ex"])
           )

    assert has_element?(view, "h2", "lib/live_preview.ex")
    assert has_element?(view, ~s(button.lg\\:hidden), "Find file")
    refute has_element?(view, ~s(button.lg\\:inline-flex))

    assert has_element?(
             view,
             ~s(a[href="/packages/live_preview/1.0.0/files/lib/live_preview.ex"]),
             "Files"
           )

    refute has_element?(view, "select")
  end

  test "highlights HEEx", %{conn: conn} do
    put_release("heex_preview", "1.0.0", [
      {"README.md", "readme"},
      {"lib/page.html.heex", "<div><%= @x %></div>\n"}
    ])

    {:ok, view, html} =
      live(conn, "/packages/heex_preview/1.0.0/files/lib/page.html.heex")

    assert has_element?(view, "h2", "lib/page.html.heex")
    assert html =~ ~s(class="l-tag">div</span>)
  end

  test "defaults the Files tab to the README and rejects unknown paths", %{conn: conn} do
    put_release("select_preview", "1.0.0", [
      {"README.md", "readme"},
      {"mix.exs", "mix"}
    ])

    {:ok, view, _html} = live(conn, "/packages/select_preview/1.0.0/files")
    assert has_element?(view, "h2", "README.md")

    view
    |> element(~s(aside a[href="/packages/select_preview/1.0.0/files/mix.exs"]), "mix.exs")
    |> render_click()

    assert_patch(view, "/packages/select_preview/1.0.0/files/mix.exs")
    assert page_title(view) == "mix.exs - select_preview 1.0.0 | Hex"
    assert has_element?(view, "h2", "mix.exs")

    assert_raise HexpmWeb.PreviewLive.NotFoundError, fn ->
      live(conn, "/packages/select_preview/1.0.0/files/not/a/file")
    end
  end

  test "renders binary and oversized file messages", %{conn: conn} do
    put_release("message_preview", "1.0.0", [
      {"binary.bin", <<0xFF>>},
      {"large.txt", String.duplicate("x", 200_001)}
    ])

    {:ok, _view, html} =
      live(conn, "/packages/message_preview/1.0.0/files/binary.bin")

    assert html =~ "Contents for binary files are not shown."

    {:ok, _view, html} = live(conn, "/packages/message_preview/1.0.0/files/large.txt")
    assert html =~ "File is too large to be displayed (0.2 MB)."
  end

  test "renders only the top level of the tree and every path for the client", %{conn: conn} do
    files =
      [{"README.md", "readme"}, {"lib/tricky/d'x(1)!.ex", "punctuation"}] ++
        for index <- 1..500 do
          {"lib/generated/deep/file_#{index}.ex", "value = #{index}\n"}
        end

    put_release("large_manifest", "1.0.0", files)
    {:ok, view, html} = live(conn, "/packages/large_manifest/1.0.0/files")

    assert has_element?(view, ~s(aside details[data-dir-path="lib"] summary), "lib")

    # Nothing below the closed directory is rendered, and none of its 500 files
    # reach the document, but the client still gets every path to search and to
    # build those children from.
    refute has_element?(view, ~s(aside details details summary), "generated")
    refute has_element?(view, ~s(aside a[href$="file_1.ex"]))
    refute has_element?(view, ~s(aside a[href$="file_500.ex"]))

    paths = file_paths(html)
    assert "lib/generated/deep/file_1.ex" in paths
    assert "lib/generated/deep/file_500.ex" in paths
    assert length(paths) == 502

    # Encoded by the router's own rule, so a link is the base plus one of these
    # and the client never spells the encoding out a second time.
    raw = template_html(html, "file-paths")
    assert raw =~ "lib/tricky/d%27x%281%29%21.ex"
    refute raw =~ "d'x(1)!.ex"

    # The client clones these, so they carry the attributes it fills in and the
    # ones LiveView needs for patch navigation.
    file_template = template_html(html, "tree-file")
    assert file_template =~ ~s(data-phx-link="patch")
    assert file_template =~ "data-name"

    dir_template = template_html(html, "tree-dir")
    assert dir_template =~ "<details"
    assert dir_template =~ "data-children"
    assert dir_template =~ "data-name"

    assert has_element?(view, ~s(template[data-finder-item]))

    # The client keys its cached nodes and index on this, so it has to identify
    # the tree, not just the version.
    assert has_element?(
             view,
             ~s(aside[phx-hook="FileFinder"][data-tree-version="hexpm/large_manifest/1.0.0"])
           )

    # A cloned directory must start closed and unfilled, or every client-built
    # directory would render pre-expanded and never fill. Matched against the
    # tag itself because a Tailwind class in the summary contains "open".
    refute dir_template =~ ~r/<details[^>]*\sopen[\s>]/
    refute dir_template =~ "data-filled"

    assert has_element?(
             view,
             ~s(aside[data-file-href-base="/packages/large_manifest/1.0.0/files"])
           )

    assert has_element?(view, ~s(div[data-tree-container][phx-update="ignore"]))
    refute has_element?(view, ~s(form#preview-tree-search[phx-change]))
    refute has_element?(view, ~s(form#preview-file-finder[phx-change]))
  end

  test "opens the directories leading to the file on screen", %{conn: conn} do
    put_release("deep_manifest", "1.0.0", [
      {"README.md", "readme"},
      {"lib/generated/deep/shown.ex", "shown"},
      {"lib/generated/deep/sibling.ex", "sibling"},
      {"lib/other/hidden.ex", "hidden"}
    ])

    {:ok, view, _html} =
      live(conn, "/packages/deep_manifest/1.0.0/files/lib/generated/deep/shown.ex")

    for path <- ["lib", "lib/generated", "lib/generated/deep"] do
      assert has_element?(view, ~s(aside details[data-dir-path="#{path}"][open]))
    end

    # The file itself and its siblings are rendered, so the sidebar shows where
    # you are without waiting on the client.
    assert has_element?(view, ~s(aside a[data-path="lib/generated/deep/shown.ex"]), "shown.ex")
    assert has_element?(view, ~s(aside a[data-path="lib/generated/deep/sibling.ex"]))

    # Branches the file is not under stay closed.
    assert has_element?(view, ~s(aside details[data-dir-path="lib/other"]))
    refute has_element?(view, ~s(aside details[data-dir-path="lib/other"][open]))
    refute has_element?(view, ~s(aside a[data-path="lib/other/hidden.ex"]))
  end

  test "caps how many children a wide directory renders", %{conn: conn} do
    limit = HexpmWeb.PreviewLive.children_limit()
    wide = for index <- 1..(limit * 3), do: {"lib/model/file_#{index}.ex", "v\n"}

    put_release("wide_manifest", "1.0.0", [{"README.md", "readme"} | wide])

    {:ok, view, html} = live(conn, "/packages/wide_manifest/1.0.0/files/lib/model/file_1.ex")

    rendered = length(Regex.scan(~r/data-path="lib\/model\//, hd(String.split(html, "l-line"))))
    assert rendered == limit

    # Not filled, so the client rebuilds the directory and pages through the rest.
    refute has_element?(view, ~s(details[data-dir-path="lib/model"] > div[data-filled="true"]))

    # It still has every path to page through, and the control to do it with.
    assert length(file_paths(html)) == limit * 3 + 1
    assert template_html(html, "tree-more") =~ "data-tree-more-button"

    assert has_element?(
             view,
             ~s(aside[data-children-limit="#{limit}"])
           )
  end

  test "marks an open directory filled and leaves a closed one for the client", %{conn: conn} do
    put_release("filled_manifest", "1.0.0", [
      {"README.md", "readme"},
      {"lib/shown.ex", "shown"},
      {"lib/other/hidden.ex", "hidden"}
    ])

    {:ok, view, _html} = live(conn, "/packages/filled_manifest/1.0.0/files/lib/shown.ex")

    # data-filled is the whole handshake: set means the server already rendered
    # the children, absent means the client must build them. Getting it wrong
    # either double-renders or leaves the directory permanently empty.
    assert has_element?(
             view,
             ~s(details[data-dir-path="lib"] > div[data-children][data-filled="true"])
           )

    assert has_element?(view, ~s(details[data-dir-path="lib/other"] > div[data-children]))

    refute has_element?(
             view,
             ~s(details[data-dir-path="lib/other"] > div[data-filled="true"])
           )
  end

  test "a name that is both a file and a directory renders as the directory", %{conn: conn} do
    # A hex tarball cannot produce this, since the file list comes from a real
    # unpacked tree. Pinned because the client makes the same choice, and the two
    # rendering the same name differently would be worse than either choice.
    put_release("collision_manifest", "1.0.0", [
      {"README.md", "readme"},
      {"lib", "a file called lib"},
      {"lib/inner.ex", "inner"}
    ])

    {:ok, view, _html} = live(conn, "/packages/collision_manifest/1.0.0/files/lib/inner.ex")

    assert has_element?(view, ~s(aside details[data-dir-path="lib"][open]))
    assert has_element?(view, ~s(aside a[data-path="lib/inner.ex"]))
    refute has_element?(view, ~s(aside a[data-path="lib"]))
  end

  test "survives a file list entry whose segments do not rejoin to it", %{conn: conn} do
    # Path.safe_relative normalises a trailing slash away, so a tarball cannot
    # produce this either. It is pinned because grouping by segment index used to
    # hand Path.join a nil and take the whole LiveView down with a 500.
    put_release("odd_manifest", "1.0.0", [
      {"README.md", "readme"},
      {"lib/dir/", "a directory-shaped entry"},
      {"lib/dir/inner.ex", "inner"}
    ])

    {:ok, view, _html} = live(conn, "/packages/odd_manifest/1.0.0/files/lib/dir/inner.ex")

    assert has_element?(view, "h2", "lib/dir/inner.ex")
    assert has_element?(view, ~s(aside details[data-dir-path="lib/dir"][open]))
    assert has_element?(view, ~s(aside a[data-path="lib/dir/inner.ex"]))
  end

  test "leaves the tree alone when patching within a version", %{conn: conn} do
    put_release("patch_manifest", "1.0.0", [
      {"README.md", "readme"},
      {"lib/a/one.ex", "one"},
      {"lib/b/two.ex", "two"}
    ])

    {:ok, view, _html} = live(conn, "/packages/patch_manifest/1.0.0/files/lib/a/one.ex")
    assert has_element?(view, ~s(aside details[data-dir-path="lib/a"][open]))

    render_patch(view, "/packages/patch_manifest/1.0.0/files/lib/b/two.ex")

    # The tree container is phx-update="ignore", so the server does not move the
    # open branch and does not render the newly shown file. Reconciling that is
    # the client's job, driven by data-active-path, which does update.
    assert has_element?(view, ~s(aside[data-active-path="lib/b/two.ex"]))
    assert has_element?(view, ~s(aside details[data-dir-path="lib/a"][open]))
    refute has_element?(view, ~s(aside a[data-path="lib/b/two.ex"]))

    # Every path is still in the payload, which is what the client rebuilds from.
    assert "lib/b/two.ex" in file_paths(render(view))
  end

  test "version picker preserves the selected filename", %{conn: conn} do
    package =
      put_release("versioned_preview", "1.0.0", [
        {"README.md", "one"},
        {"lib/shared.ex", "one"}
      ])

    put_release(
      "versioned_preview",
      "2.0.0",
      [{"README.md", "two"}],
      package
    )

    {:ok, view, _html} =
      live(conn, "/packages/versioned_preview/1.0.0/files/lib/shared.ex")

    assert has_element?(
             view,
             ~s(a[href="/packages/versioned_preview/2.0.0/files/lib/shared.ex?fallback=default"]),
             "2.0.0"
           )

    {:ok, direct_view, _html} =
      live(conn, "/packages/versioned_preview/1.0.0/files/lib/shared.ex?fallback=default")

    assert has_element?(direct_view, "h2", "shared.ex")

    conn = get(conn, "/packages/versioned_preview/2.0.0/files/lib/shared.ex?fallback=default")

    assert html_response(conn, 200) =~
             HexpmWeb.Endpoint.url() <>
               ~s(/packages/versioned_preview/2.0.0/files/README.md" rel="canonical")

    {:ok, fallback_view, _html} = live(conn)

    assert has_element?(fallback_view, "h2", "README.md")

    render_patch(view, "/packages/versioned_preview/2.0.0/files/lib/shared.ex?fallback=default")
    assert_patch(view, "/packages/versioned_preview/2.0.0/files/README.md")
    assert has_element?(view, "h2", "README.md")
  end

  test "returns 404 when package or file data is missing", %{conn: conn} do
    assert_raise HexpmWeb.PreviewLive.NotFoundError, fn ->
      live(conn, "/packages/missing/1.0.0/files")
    end

    package = insert(:package, name: "empty_preview")
    insert(:release, package: package, version: "1.0.0")

    Hexpm.Store.put(
      :preview_bucket,
      "file_lists/empty_preview-1.0.0.json",
      Jason.encode!([])
    )

    assert_raise HexpmWeb.PreviewLive.NotFoundError, fn ->
      live(conn, "/packages/empty_preview/1.0.0/files")
    end
  end

  test "renders private package files for organization members", %{conn: conn} do
    %{repository: repository, user: user} = private_release("private_live_preview", "1.0.0")

    {:ok, view, _html} =
      conn
      |> test_login(user)
      |> live("/packages/#{repository.name}/private_live_preview/1.0.0/files/mix.exs")

    assert has_element?(view, "h2", "mix.exs")

    assert has_element?(view, ~s(aside details[data-dir-path="lib"] summary), "lib")

    assert has_element?(
             view,
             ~s(aside[data-file-href-base="/packages/#{repository.name}/private_live_preview/1.0.0/files"])
           )

    assert has_element?(
             view,
             ~s(a[href="/packages/#{repository.name}/private_live_preview/1.0.0/raw/mix.exs"]),
             "Raw"
           )
  end

  test "returns 404 for private packages to non-members and anonymous users", %{conn: conn} do
    %{repository: repository} = private_release("private_denied_preview", "1.0.0")
    other_user = insert(:user)

    assert_raise HexpmWeb.PreviewLive.NotFoundError, fn ->
      live(conn, "/packages/#{repository.name}/private_denied_preview/1.0.0/files")
    end

    assert_raise HexpmWeb.PreviewLive.NotFoundError, fn ->
      conn
      |> test_login(other_user)
      |> live("/packages/#{repository.name}/private_denied_preview/1.0.0/files")
    end

    assert_raise HexpmWeb.PreviewLive.NotFoundError, fn ->
      live(conn, "/packages/private_denied_preview/1.0.0/files")
    end
  end

  defp private_release(package_name, version) do
    repository = insert(:repository)
    user = insert(:user)
    insert(:organization_user, user: user, organization: repository.organization)
    package = insert(:package, repository_id: repository.id, name: package_name)
    insert(:release, package: package, version: version)

    files = [{"mix.exs", "mix"}, {"lib/private.ex", "private"}]
    prefix = "repos/#{repository.name}/"

    Hexpm.Store.put(
      :preview_bucket,
      "#{prefix}file_lists/#{package_name}-#{version}.json",
      Jason.encode!(Enum.map(files, &elem(&1, 0)))
    )

    for {filename, contents} <- files do
      Hexpm.Store.put(
        :preview_bucket,
        "#{prefix}files/#{package_name}/#{version}/#{filename}",
        contents
      )
    end

    %{repository: repository, user: user, package: package}
  end

  defp put_release(package_name, version, files, package \\ nil) do
    package = package || insert(:package, name: package_name)
    insert(:release, package: package, version: version)

    Hexpm.Store.put(
      :preview_bucket,
      "file_lists/#{package_name}-#{version}.json",
      Jason.encode!(Enum.map(files, &elem(&1, 0)))
    )

    for {filename, contents} <- files do
      Hexpm.Store.put(
        :preview_bucket,
        "files/#{package_name}/#{version}/#{filename}",
        contents
      )
    end

    package
  end
end
