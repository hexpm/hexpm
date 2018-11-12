defmodule HexpmWeb.PackageViewTest do
  use HexpmWeb.ConnCase, async: true

  alias HexpmWeb.PackageView

  defp parse_html_list_to_string(html_map) do
    Enum.map_join(html_map, fn x ->
      if is_tuple(x), do: Phoenix.HTML.safe_to_string(x), else: x
    end)
  end

  test "show sort info" do
    assert PackageView.show_sort_info(:name) == "Sort: Name"
    assert PackageView.show_sort_info(:inserted_at) == "Sort: Recently created"
    assert PackageView.show_sort_info(:updated_at) == "Sort: Recently updated"
    assert PackageView.show_sort_info(:total_downloads) == "Sort: Total downloads"
    assert PackageView.show_sort_info(:recent_downloads) == "Sort: Recent downloads"
    assert PackageView.show_sort_info(nil) == "Sort: Name"
  end

  test "show sort info when sort param is not available" do
    assert PackageView.show_sort_info("some param") == nil
  end

  describe "dep_snippet/3" do
    test "format simple mix dependency snippet" do
      version = Version.parse!("1.0.0")
      package = %{name: "ecto", organization: %{name: "hexpm"}}
      release = %{meta: %{app: package.name}, version: version}
      assert PackageView.dep_snippet(:mix, package, release) == ~s({:ecto, "~> 1.0"})
    end

    test "format mix dependency snippet" do
      version = Version.parse!("1.0.0")
      package = %{name: "timex", organization: %{name: "hexpm"}}
      release = %{meta: %{app: "extime"}, version: version}

      assert PackageView.dep_snippet(:mix, package, release) ==
               ~s({:extime, "~> 1.0", hex: :timex})
    end

    test "format private mix dependency snippet" do
      version = Version.parse!("1.0.0")
      package = %{name: "ecto", organization: %{name: "private"}}
      release = %{meta: %{app: package.name}, version: version}

      assert PackageView.dep_snippet(:mix, package, release) ==
               ~s({:ecto, "~> 1.0", organization: "private"})
    end

    test "format simple rebar dependency snippet" do
      version = Version.parse!("1.0.0")
      package = %{name: "rebar"}
      release = %{meta: %{app: package.name}, version: version}
      assert PackageView.dep_snippet(:rebar, package, release) == ~s({rebar, "1.0.0"})
    end

    test "format rebar dependency snippet" do
      version = Version.parse!("1.0.1")
      package = %{name: "rebar"}
      release = %{meta: %{app: "erlang_mk"}, version: version}

      assert PackageView.dep_snippet(:rebar, package, release) ==
               ~s({erlang_mk, "1.0.1", {pkg, rebar}})
    end

    test "format erlang.mk dependency snippet" do
      version = Version.parse!("1.0.4")
      package = %{name: "cowboy"}
      release = %{meta: %{app: package.name}, version: version}
      assert PackageView.dep_snippet(:erlang_mk, package, release) == "dep_cowboy = hex 1.0.4"
    end

    test "escape mix application name" do
      version = Version.parse!("1.0.0")
      package = %{name: "lfe_app", organization: %{name: "hexpm"}}
      release = %{meta: %{app: "lfe-app"}, version: version}

      assert PackageView.dep_snippet(:mix, package, release) ==
               ~s({:"lfe-app", "~> 1.0", hex: :lfe_app})
    end

    test "escape rebar application name" do
      version = Version.parse!("1.0.1")
      package = %{name: "lfe_app"}
      release = %{meta: %{app: "lfe-app"}, version: version}

      assert PackageView.dep_snippet(:rebar, package, release) ==
               ~s({'lfe-app', "1.0.1", {pkg, lfe_app}})
    end
  end

  test "mix config version" do
    version0 = %Version{major: 0, minor: 0, patch: 1, pre: ["dev", 0, 1]}
    version1 = %Version{major: 0, minor: 0, patch: 2, pre: []}
    version2 = %Version{major: 0, minor: 2, patch: 99, pre: []}
    version3 = %Version{major: 2, minor: 0, patch: 2, pre: []}

    assert PackageView.snippet_version(:mix, version0) == "~> 0.0.1-dev.0.1"
    assert PackageView.snippet_version(:mix, version1) == "~> 0.0.2"
    assert PackageView.snippet_version(:mix, version2) == "~> 0.2.99"
    assert PackageView.snippet_version(:mix, version3) == "~> 2.0"
  end

  test "rebar and erlang.mk config version" do
    version0 = %Version{major: 0, minor: 0, patch: 1, pre: ["dev", 0, 1]}
    version1 = %Version{major: 0, minor: 0, patch: 2, pre: []}
    version2 = %Version{major: 0, minor: 2, patch: 99, pre: []}
    version3 = %Version{major: 2, minor: 0, patch: 2, pre: []}

    assert PackageView.snippet_version(:rebar, version0) == "0.0.1-dev.0.1"
    assert PackageView.snippet_version(:rebar, version1) == "0.0.2"
    assert PackageView.snippet_version(:rebar, version2) == "0.2.99"
    assert PackageView.snippet_version(:rebar, version3) == "2.0.2"

    assert PackageView.snippet_version(:erlang_mk, version0) == "0.0.1-dev.0.1"
    assert PackageView.snippet_version(:erlang_mk, version1) == "0.0.2"
    assert PackageView.snippet_version(:erlang_mk, version2) == "0.2.99"
    assert PackageView.snippet_version(:erlang_mk, version3) == "2.0.2"
  end

  describe "retirement_message/1" do
    test "reason is 'other', message contains text" do
      retirement = %{reason: "other", message: "something went terribly wrong"}

      assert IO.iodata_to_binary(PackageView.retirement_message(retirement)) ==
               "Retired package: something went terribly wrong"
    end

    test "reason is 'other', message is empty" do
      retirement = %{reason: "other", message: nil}
      assert IO.iodata_to_binary(PackageView.retirement_message(retirement)) == "Retired package"
    end

    test "reason is not 'other', message contains text" do
      retirement = %{reason: "security", message: "something went terribly wrong"}

      assert IO.iodata_to_binary(PackageView.retirement_message(retirement)) ==
               "Retired package: Security issue - something went terribly wrong"
    end

    test "reason is not 'other', message is empty" do
      retirement = %{reason: "security", message: nil}

      assert IO.iodata_to_binary(PackageView.retirement_message(retirement)) ==
               "Retired package: Security issue"
    end
  end

  describe "retirement_html/1" do
    test "reason is 'other', message contains text" do
      retirement =
        PackageView.retirement_html(%{reason: "other", message: "something went terribly wrong"})

      assert parse_html_list_to_string(retirement) ==
               "<strong>Retired package:</strong> something went terribly wrong"
    end

    test "reason is 'other', message is empty" do
      retirement = PackageView.retirement_html(%{reason: "other", message: nil})
      assert parse_html_list_to_string(retirement) == "<strong>Retired package</strong>"
    end

    test "reason is not 'other', message contains text" do
      retirement =
        PackageView.retirement_html(%{
          reason: "security",
          message: "something went terribly wrong"
        })

      assert parse_html_list_to_string(retirement) ==
               "<strong>Retired package:</strong> Security issue - something went terribly wrong"
    end

    test "reason is not 'other', message is empty" do
      retirement = PackageView.retirement_html(%{reason: "security", message: nil})

      assert parse_html_list_to_string(retirement) ==
               "<strong>Retired package:</strong> Security issue"
    end
  end
end
