defmodule Hexpm.UtilsTest do
  use ExUnit.Case, async: true

  alias Hexpm.Utils

  describe "tree_regular_files/1" do
    test "lists regular files and never follows symlinks" do
      root = Path.join(System.tmp_dir!(), "tree-files-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(root, "sub/nested"))
      File.write!(Path.join(root, "top.txt"), "top")
      File.write!(Path.join(root, "sub/nested/deep.txt"), "deep")
      File.ln_s!("..", Path.join(root, "sub/loop"))
      File.ln_s!("top.txt", Path.join(root, "link.txt"))
      on_exit(fn -> File.rm_rf!(root) end)

      assert Enum.sort(Utils.tree_regular_files(root)) == ["sub/nested/deep.txt", "top.txt"]
    end
  end

  describe "datetime_to_rfc2822" do
    test "formats sample timestamps correctly" do
      assert Utils.datetime_to_rfc2822(~U[2002-09-07 09:42:31Z]) ==
               "Sat, 07 Sep 2002 09:42:31 GMT"

      assert Utils.datetime_to_rfc2822(~U[2020-02-23 19:47:26Z]) ==
               "Sun, 23 Feb 2020 19:47:26 GMT"
    end
  end

  describe "safe_int/1" do
    test "handles various input types" do
      assert Utils.safe_int("707") == 707
      assert Utils.safe_int("abc") == nil
      assert Utils.safe_int(nil) == nil
      assert Utils.safe_int(%{"page" => "707"}) == nil
      assert Utils.safe_int(707) == nil
    end
  end

  describe "safe_date/1" do
    test "handles various input types" do
      assert Utils.safe_date("2024-01-15") == ~D[2024-01-15]
      assert Utils.safe_date("invalid") == nil
      assert Utils.safe_date(nil) == nil
      assert Utils.safe_date(%{"date" => "2024-01-15"}) == nil
    end
  end

  describe "safe_to_atom/2" do
    test "handles various input types" do
      assert Utils.safe_to_atom("foo", ~w(foo bar)) == :foo
      assert Utils.safe_to_atom("baz", ~w(foo bar)) == nil
      assert Utils.safe_to_atom(%{"key" => "foo"}, ~w(foo bar)) == nil
    end
  end

  test "raise_async_stream_error/1 preserves successful results and reraises exits" do
    assert Utils.raise_async_stream_error(ok: :value) |> Enum.to_list() == [ok: :value]

    assert_raise RuntimeError, ~r/failure/, fn ->
      [{:exit, {RuntimeError.exception("failure"), []}}]
      |> Utils.raise_async_stream_error()
      |> Stream.run()
    end
  end

  describe "within_last_day?/1" do
    setup do
      %{now: ~N[2026-07-11 12:00:00]}
    end

    test "returns true for current time", %{now: now} do
      assert Utils.within_last_day?(now, now)
    end

    test "returns true for timestamp less than 24 hours ago", %{now: now} do
      timestamp = NaiveDateTime.add(now, -23 * 60 * 60, :second)
      assert Utils.within_last_day?(timestamp, now)
    end

    test "returns false for timestamp more than 24 hours ago", %{now: now} do
      timestamp = NaiveDateTime.add(now, -25 * 60 * 60, :second)
      refute Utils.within_last_day?(timestamp, now)
    end

    test "returns false for timestamp exactly 24 hours ago", %{now: now} do
      timestamp = NaiveDateTime.add(now, -86_400, :second)
      refute Utils.within_last_day?(timestamp, now)
    end

    test "returns false for timestamp many days ago", %{now: now} do
      timestamp = NaiveDateTime.add(now, -1_000_000, :second)
      refute Utils.within_last_day?(timestamp, now)
    end
  end

  describe "current_docs_html_url/3" do
    setup do
      hexpm = %Hexpm.Repository.Repository{id: 1, name: "hexpm"}
      package = %Hexpm.Repository.Package{name: "decimal", repository: hexpm}
      current = %Hexpm.Repository.Release{version: Version.parse!("1.2.3")}
      older = %Hexpm.Repository.Release{version: Version.parse!("1.0.0")}
      %{package: package, current: current, older: older}
    end

    test "returns nil when no release has docs", %{package: package, current: current} do
      assert is_nil(Utils.current_docs_html_url(package, current, nil))
    end

    test "returns nil with no current release and no docs", %{package: package} do
      assert is_nil(Utils.current_docs_html_url(package, nil, nil))
    end

    test "returns the version-specific URL when current matches latest-with-docs", %{
      package: package,
      current: current
    } do
      url = Utils.current_docs_html_url(package, current, current)
      assert url =~ "//decimal."
      assert url =~ "1.2.3"
    end

    test "returns the un-versioned URL when current differs from latest-with-docs", %{
      package: package,
      current: current,
      older: older
    } do
      url = Utils.current_docs_html_url(package, current, older)
      assert url =~ "//decimal."
      refute url =~ "1.2.3"
      refute url =~ "1.0.0"
    end

    test "returns the un-versioned URL when current_release is nil but latest has docs", %{
      package: package,
      older: older
    } do
      url = Utils.current_docs_html_url(package, nil, older)
      assert url =~ "//decimal."
      refute url =~ "1.0.0"
    end

    test "maps underscores in the package name to hyphens in the subdomain" do
      hexpm = %Hexpm.Repository.Repository{id: 1, name: "hexpm"}
      package = %Hexpm.Repository.Package{name: "phoenix_live_view", repository: hexpm}
      release = %Hexpm.Repository.Release{version: Version.parse!("1.0.0")}

      url = Utils.docs_html_url(hexpm, package, release)

      assert url =~ "//phoenix-live-view."
      refute url =~ "phoenix_live_view"
    end

    test "maps underscores in the org repository name to hyphens in the subdomain" do
      repository = %Hexpm.Repository.Repository{id: 2, name: "my_org"}
      package = %Hexpm.Repository.Package{name: "secret", repository: repository}
      release = %Hexpm.Repository.Release{version: Version.parse!("1.0.0")}

      url = Utils.docs_html_url(repository, package, release)

      assert url =~ "//my-org."
      refute url =~ "my_org"
    end
  end

  describe "docs_html_url/3 with repository and package names" do
    test "builds public package URLs from the shared docs URL" do
      assert Utils.docs_html_url("hexpm", "phoenix_live_view", "/1.0.0") ==
               "http://phoenix-live-view.localhost:5002/1.0.0"
    end

    test "builds private package URLs from the shared private docs URL" do
      assert Utils.docs_html_url("my_org", "secret", "/1.0.0") ==
               "http://my-org.localhost:5002/secret/1.0.0"
    end

    # The docs CDN routes search.hexdocs.pm to the search backend, so the
    # package of that name is served from the apex and nowhere else.
    test "keeps packages named after a reserved subdomain on the apex" do
      assert Utils.docs_html_url("hexpm", "search", "/Search.html") ==
               "http://localhost:5002/search/Search.html"

      hexpm = %Hexpm.Repository.Repository{id: 1, name: "hexpm"}
      package = %Hexpm.Repository.Package{name: "search", repository: hexpm}
      release = %Hexpm.Repository.Release{version: Version.parse!("0.3.0")}

      assert Utils.docs_html_url(hexpm, package, release) ==
               "http://localhost:5002/search/0.3.0/"
    end
  end
end
