defmodule HexpmWeb.PreviewLiveTest do
  use HexpmWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup do
    %{conn: build_conn()}
  end

  test "renders the latest source with syntax highlighting", %{conn: conn} do
    put_release("live_preview", "1.0.0", [
      {"README.md", "readme"},
      {"lib/live_preview.ex", "defmodule LivePreview do\nend\n"}
    ])

    {:ok, view, html} = live(conn, "/preview/live_preview/show/lib/live_preview.ex")

    assert html =~ "live_preview"
    assert html =~ "1.0.0"
    assert html =~ "PreviewLineHighlight"
    assert html =~ "l-line"
    assert has_element?(view, "h2", "lib/live_preview.ex")
  end

  test "highlights HEEx and accepts a filename query parameter", %{conn: conn} do
    put_release("heex_preview", "1.0.0", [
      {"README.md", "readme"},
      {"lib/page.html.heex", "<div><%= @x %></div>\n"}
    ])

    {:ok, view, html} =
      live(conn, "/preview/heex_preview/1.0.0?filename=lib%2Fpage.html.heex")

    assert has_element?(view, "h2", "lib/page.html.heex")
    assert html =~ ~s(class="l-tag">div</span>)
  end

  test "defaults unknown files and changes files with a patch", %{conn: conn} do
    put_release("select_preview", "1.0.0", [
      {"README.md", "readme"},
      {"mix.exs", "mix"}
    ])

    {:ok, view, _html} = live(conn, "/preview/select_preview/1.0.0/show/not/a/file")
    assert has_element?(view, "h2", "README.md")

    render_change(view, "select_file", %{"file" => "mix.exs"})
    assert_patch(view, "/preview/select_preview/1.0.0/show/mix.exs")
    assert has_element?(view, "h2", "mix.exs")
  end

  test "renders binary and oversized file messages", %{conn: conn} do
    put_release("message_preview", "1.0.0", [
      {"binary.bin", <<0xFF>>},
      {"large.txt", String.duplicate("x", 2_000_001)}
    ])

    {:ok, _view, html} = live(conn, "/preview/message_preview/1.0.0/show/binary.bin")
    assert html =~ "Contents for binary files are not shown."

    {:ok, _view, html} = live(conn, "/preview/message_preview/1.0.0/show/large.txt")
    assert html =~ "File is too large to be displayed (2.0 MB)."
  end

  test "returns 404 when Preview data is missing", %{conn: conn} do
    assert_raise HexpmWeb.PreviewLive.NotFoundError, fn ->
      live(conn, "/preview/missing")
    end

    Hexpm.Store.put(:preview_bucket, "latest_versions/empty", "1.0.0")
    Hexpm.Store.put(:preview_bucket, "file_lists/empty-1.0.0.json", Jason.encode!([]))

    assert_raise HexpmWeb.PreviewLive.NotFoundError, fn ->
      live(conn, "/preview/empty")
    end
  end

  defp put_release(package, version, files) do
    Hexpm.Store.put(:preview_bucket, "latest_versions/#{package}", version)

    Hexpm.Store.put(
      :preview_bucket,
      "file_lists/#{package}-#{version}.json",
      Jason.encode!(Enum.map(files, &elem(&1, 0)))
    )

    for {filename, contents} <- files do
      Hexpm.Store.put(:preview_bucket, "files/#{package}/#{version}/#{filename}", contents)
    end
  end
end
