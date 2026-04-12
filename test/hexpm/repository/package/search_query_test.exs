defmodule Hexpm.Repository.Package.SearchQueryTest do
  use ExUnit.Case, async: true

  alias Hexpm.Repository.Package.SearchQuery

  describe "parse/1" do
    test "nil and empty string return an empty query" do
      assert SearchQuery.parse(nil) == {:ok, %SearchQuery{}}
      assert SearchQuery.parse("") == {:ok, %SearchQuery{}}
      assert SearchQuery.parse("   ") == {:ok, %SearchQuery{}}
    end

    test "plain text is captured as free_text" do
      assert SearchQuery.parse("phoenix") == {:ok, %SearchQuery{free_text: "phoenix"}}
    end

    test "a single filter is captured" do
      assert SearchQuery.parse("build_tool:mix") == {:ok, %SearchQuery{build_tools: ["mix"]}}
    end

    test "updated_after is captured as a raw string" do
      {:ok, q} = SearchQuery.parse("updated_after:2025-01-01T00:00:00Z")
      assert q.updated_after == "2025-01-01T00:00:00Z"
    end

    test "description is captured" do
      {:ok, q} = SearchQuery.parse("description:authentication")
      assert q.description == "authentication"
    end

    test "mixed free text and filters" do
      {:ok, q} = SearchQuery.parse("phoenix build_tool:mix depends:ecto")
      assert q.free_text == "phoenix"
      assert q.build_tools == ["mix"]
      assert q.depends == "ecto"
    end

    test "repeated build_tool filters accumulate" do
      {:ok, q} = SearchQuery.parse("build_tool:mix build_tool:rebar3")
      assert q.build_tools == ["mix", "rebar3"]
    end

    test "repeated extra filters accumulate as {key, value} tuples" do
      {:ok, q} = SearchQuery.parse("extra:license,MIT extra:maintenance,active")
      assert q.extra == [{"license", "MIT"}, {"maintenance", "active"}]
    end

    test "quoted values preserve spaces" do
      {:ok, q} = SearchQuery.parse(~s(name:"my package" build_tool:mix))
      assert q.name == "my package"
      assert q.build_tools == ["mix"]
    end

    test "unknown filter operators round-trip via :unknown" do
      {:ok, q} = SearchQuery.parse("foo:bar build_tool:mix")
      assert q.unknown == [{"foo", "bar"}]
      assert q.build_tools == ["mix"]
    end

    test "malformed extra value returns an error" do
      assert {:error, {:extra, _}} = SearchQuery.parse("extra:no_comma_here")
    end
  end
end
