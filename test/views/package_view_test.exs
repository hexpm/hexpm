defmodule HexWeb.PackageViewTest do
  use HexWeb.ConnCase, async: true

  alias HexWeb.PackageView

  test "show sort info" do
    assert PackageView.show_sort_info("name") == "(Sorted by name)"
    assert PackageView.show_sort_info("inserted_at") == "(Sorted by recently created)"
    assert PackageView.show_sort_info("updated_at") == "(Sorted by recently updated)"
    assert PackageView.show_sort_info("downloads") == "(Sorted by downloads)"
  end

  test "show sort info when sort param is not available" do
    assert PackageView.show_sort_info("some param") == nil
  end

  test "show sort info when sort param is nil" do
    assert PackageView.show_sort_info(nil) == "(Sorted by name)"
  end

  test "format simple mix dependency snippet" do
    version = Version.parse!("1.0.0")
    package_name   = "ecto"
    release = %{meta: %{app: package_name}, version: version}
    assert PackageView.dep_snippet(:mix, package_name, release) == "{:ecto, \"~> 1.0\"}"
  end

  test "format mix dependency snippet" do
    version = Version.parse!("1.0.0")
    package_name   = "timex"
    release = %{meta: %{app: "extime"}, version: version}
    assert PackageView.dep_snippet(:mix, package_name, release) == "{:extime, \"~> 1.0\", hex: :timex}"
  end

  test "format simple rebar dependency snippet" do
    version = Version.parse!("1.0.0")
    package_name   = "rebar"
    release = %{meta: %{app: package_name}, version: version}
    assert PackageView.dep_snippet(:rebar, package_name, release) == "{rebar, \"1.0.0\"}"
  end

  test "format rebar dependency snippet" do
    version = Version.parse!("1.0.1")
    package_name   = "rebar"
    release = %{meta: %{app: "erlang_mk"}, version: version}
    assert PackageView.dep_snippet(:rebar, package_name, release) == "{erlang_mk, \"1.0.1\", {pkg, rebar}}"
  end

  test "format erlang.mk dependency snippet" do
    version = Version.parse!("1.0.4")
    package_name   = "cowboy"
    release = %{meta: %{app: package_name}, version: version}
    assert PackageView.dep_snippet(:erlang_mk, package_name, release) == "dep_cowboy = hex 1.0.4"
  end

  test "escape mix application name" do
    version = Version.parse!("1.0.0")
    package_name   = "lfe_app"
    release = %{meta: %{app: "lfe-app"}, version: version}
    assert PackageView.dep_snippet(:mix, package_name, release) == "{:\"lfe-app\", \"~> 1.0\", hex: :lfe_app}"
  end

  test "escape rebar application name" do
    version = Version.parse!("1.0.1")
    package_name   = "lfe_app"
    release = %{meta: %{app: "lfe-app"}, version: version}
    assert PackageView.dep_snippet(:rebar, package_name, release) == "{'lfe-app', \"1.0.1\", {pkg, lfe_app}}"
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
