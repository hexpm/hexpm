defmodule Hexpm.Web.PackageViewTest do
  use Hexpm.ConnCase, async: true

  alias Hexpm.Web.PackageView

  test "show sort info" do
    assert PackageView.show_sort_info(:name) == "(Sorted by name)"
    assert PackageView.show_sort_info(:inserted_at) == "(Sorted by recently created)"
    assert PackageView.show_sort_info(:updated_at) == "(Sorted by recently updated)"
    assert PackageView.show_sort_info(:total_downloads) == "(Sorted by total downloads)"
    assert PackageView.show_sort_info(:recent_downloads) == "(Sorted by recent downloads)"
    assert PackageView.show_sort_info(nil) == "(Sorted by name)"
  end

  test "show sort info when sort param is not available" do
    assert PackageView.show_sort_info("some param") == nil
  end

  test "show sort info when sort param is nil" do
    assert PackageView.show_sort_info(nil) == "(Sorted by name)"
  end

  describe "dep_snippet/3" do
    test "format simple mix dependency snippet" do
      version = Version.parse!("1.0.0")
      package = %{name: "ecto", repository: %{name: "hexpm"}}
      release = %{meta: %{app: package.name}, version: version}
      assert PackageView.dep_snippet(:mix, package, release) == ~s({:ecto, "~> 1.0"})
    end

    test "format mix dependency snippet" do
      version = Version.parse!("1.0.0")
      package = %{name: "timex", repository: %{name: "hexpm"}}
      release = %{meta: %{app: "extime"}, version: version}
      assert PackageView.dep_snippet(:mix, package, release) == ~s({:extime, "~> 1.0", hex: :timex})
    end

    test "format private mix dependency snippet" do
      version = Version.parse!("1.0.0")
      package = %{name: "ecto", repository: %{name: "private"}}
      release = %{meta: %{app: package.name}, version: version}
      assert PackageView.dep_snippet(:mix, package, release) == ~s({:ecto, "~> 1.0", organization: "private"})
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
      assert PackageView.dep_snippet(:rebar, package, release) == ~s({erlang_mk, "1.0.1", {pkg, rebar}})
    end

    test "format erlang.mk dependency snippet" do
      version = Version.parse!("1.0.4")
      package = %{name: "cowboy"}
      release = %{meta: %{app: package.name}, version: version}
      assert PackageView.dep_snippet(:erlang_mk, package, release) == "dep_cowboy = hex 1.0.4"
    end

    test "escape mix application name" do
      version = Version.parse!("1.0.0")
      package = %{name: "lfe_app", repository: %{name: "hexpm"}}
      release = %{meta: %{app: "lfe-app"}, version: version}
      assert PackageView.dep_snippet(:mix, package, release) == ~s({:"lfe-app", "~> 1.0", hex: :lfe_app})
    end

    test "escape rebar application name" do
      version = Version.parse!("1.0.1")
      package = %{name: "lfe_app"}
      release = %{meta: %{app: "lfe-app"}, version: version}
      assert PackageView.dep_snippet(:rebar, package, release) == ~s({'lfe-app', "1.0.1", {pkg, lfe_app}})
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

end
