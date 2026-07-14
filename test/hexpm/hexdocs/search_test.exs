defmodule Hexpm.Hexdocs.SearchTest do
  use ExUnit.Case, async: true

  alias Hexpm.Hexdocs.Search

  test "extracts explicit search language and items" do
    items = [%{"type" => "module", "title" => "Example", "ref" => "Example.html"}]
    data = "searchData=" <> Jason.encode!(%{"proglang" => "gleam", "items" => items})

    assert Search.find_search_items("package", "1.0.0", [{"search_data-package.js", data}]) ==
             {"gleam", items}
  end

  test "infers Elixir and Erlang search languages" do
    elixir = [%{"type" => "module", "title" => "Example"}]
    erlang = [%{"type" => "module", "title" => ":example"}]

    assert Search.find_search_items("package", "1.0.0", search_file(elixir)) ==
             {"elixir", elixir}

    assert Search.find_search_items("package", "1.0.0", search_file(erlang)) ==
             {"erlang", erlang}
  end

  test "returns nil for missing or empty search data" do
    assert Search.find_search_items("package", "1.0.0", []) == nil
    assert Search.find_search_items("package", "1.0.0", search_file([])) == nil
  end

  test "raises for malformed or unexpected search data" do
    assert_raise RuntimeError, ~r/Failed to decode search data json/, fn ->
      Search.find_search_items(
        "package",
        "1.0.0",
        [{"search_data-package.js", "searchData=invalid"}]
      )
    end

    assert_raise RuntimeError, ~r/Unexpected search_data format/, fn ->
      Search.find_search_items("package", "1.0.0", [{"search_data-package.js", "invalid"}])
    end

    assert_raise RuntimeError, ~r/Failed to extract search items/, fn ->
      Search.find_search_items(
        "package",
        "1.0.0",
        [{"search_data-package.js", "searchData=" <> Jason.encode!(%{})}]
      )
    end
  end

  defp search_file(items) do
    [{"search_data-package.js", "searchData=" <> Jason.encode!(%{"items" => items})}]
  end
end
