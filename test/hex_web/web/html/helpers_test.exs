defmodule HexWeb.Web.HTML.HelpersTest do
  use HexWebTest.Case

  alias HexWeb.Web.HTML.Helpers

  test "format simple mix dependency snippet" do
    package_name = "ecto"
    release = %{meta: %{"app" => package_name}}
    assert Helpers.format_dep_snippet(:mix, package_name, "~> 1.0", release) == "{:ecto, \"~> 1.0\"}"
  end

  test "format mix dependency snippet" do
    package_name = "timex"
    release = %{ meta: %{ "app" => "extime"}}
    assert Helpers.format_dep_snippet(:mix, package_name, "~> 1.0", release) == "{:extime, \"~> 1.0\", hex: :timex}"
  end

  test "format simple rebar dependency snippet" do
    package_name = "rebar"
    release = %{meta: %{"app" => package_name}}
    assert Helpers.format_dep_snippet(:rebar, package_name, "1.0.0", release) == "{rebar, \"1.0.0\"}"
  end

  test "format rebar dependency snippet" do
    package_name = "rebar"
    release = %{ meta: %{ "app" => "erlang_mk"}}
    assert Helpers.format_dep_snippet(:rebar, package_name, "1.0.1", release) == "{erlang_mk, \"1.0.1\", {pkg, rebar}}"
  end
end
