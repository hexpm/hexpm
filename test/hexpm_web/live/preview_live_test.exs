defmodule HexpmWeb.PreviewLiveTest do
  use HexpmWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup do
    %{conn: build_conn()}
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
    assert has_element?(view, ~s(a[aria-current="page"]), "live_preview.ex")
    assert has_element?(view, "h2", "lib/live_preview.ex")

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
      {"large.txt", String.duplicate("x", 2_000_001)}
    ])

    {:ok, _view, html} =
      live(conn, "/packages/message_preview/1.0.0/files/binary.bin")

    assert html =~ "Contents for binary files are not shown."

    {:ok, _view, html} = live(conn, "/packages/message_preview/1.0.0/files/large.txt")
    assert html =~ "File is too large to be displayed (2.0 MB)."
  end

  test "searches a manifest containing hundreds of files", %{conn: conn} do
    files =
      [{"README.md", "readme"}] ++
        for index <- 1..500 do
          {"lib/generated/deep/file_#{index}.ex", "value = #{index}\n"}
        end

    put_release("large_manifest", "1.0.0", files)
    {:ok, view, _html} = live(conn, "/packages/large_manifest/1.0.0/files")

    view
    |> element("#preview-tree-search")
    |> render_change(%{"query" => "deep499"})

    assert has_element?(
             view,
             ~s(a[href="/packages/large_manifest/1.0.0/files/lib/generated/deep/file_499.ex"])
           )

    refute has_element?(view, ~s(a[href$="file_498.ex"]), "file_498.ex")
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

    assert {:error, {:live_redirect, %{to: "/packages/versioned_preview/2.0.0/files/README.md"}}} =
             live(
               conn,
               "/packages/versioned_preview/2.0.0/files/lib/shared.ex?fallback=default"
             )

    {:ok, fallback_view, _html} =
      live(conn, "/packages/versioned_preview/2.0.0/files/README.md")

    assert has_element?(fallback_view, "h2", "README.md")
  end

  test "returns 404 when package or file data is missing", %{conn: conn} do
    assert_raise HexpmWeb.PreviewLive.NotFoundError, fn ->
      live(conn, "/packages/missing/1.0.0/files")
    end

    package = insert(:package, name: "empty_preview")
    insert(:release, package: package, version: "1.0.0")
    Hexpm.Store.put(:preview_bucket, "file_lists/empty_preview-1.0.0.json", Jason.encode!([]))

    assert_raise HexpmWeb.PreviewLive.NotFoundError, fn ->
      live(conn, "/packages/empty_preview/1.0.0/files")
    end
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
