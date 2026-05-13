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
      assert SearchQuery.parse("build_tool:mix") == {:ok, %SearchQuery{build_tool: "mix"}}
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
      assert q.build_tool == "mix"
      assert q.depends == "ecto"
    end

    test "repeated build_tool uses last value" do
      {:ok, q} = SearchQuery.parse("build_tool:mix build_tool:rebar3")
      assert q.build_tool == "rebar3"
    end

    test "repeated extra filters accumulate as {key, value} tuples" do
      {:ok, q} = SearchQuery.parse("extra:license,MIT extra:maintenance,active")
      assert q.extra == [{"license", "MIT"}, {"maintenance", "active"}]
    end

    test "quoted values preserve spaces" do
      {:ok, q} = SearchQuery.parse(~s(name:"my package" build_tool:mix))
      assert q.name == "my package"
      assert q.build_tool == "mix"
    end

    test "unknown filter operators round-trip via :unknown" do
      {:ok, q} = SearchQuery.parse("foo:bar build_tool:mix")
      assert q.unknown == [{"foo", "bar"}]
      assert q.build_tool == "mix"
    end

    test "malformed extra value returns an error" do
      assert {:error, {:extra, _}} = SearchQuery.parse("extra:no_comma_here")
    end

    test "a leading colon is treated as free text, not an empty-key filter" do
      {:ok, q} = SearchQuery.parse(":foo build_tool:mix")
      assert q.free_text == ":foo"
      assert q.unknown == []
      assert q.build_tool == "mix"
    end

    test "tabs and newlines separate tokens just like spaces" do
      {:ok, q} = SearchQuery.parse("build_tool:mix\tdepends:ecto\nname:phoenix")
      assert q.build_tool == "mix"
      assert q.depends == "ecto"
      assert q.name == "phoenix"
    end
  end

  describe "serialize/1" do
    test "empty query serializes to empty string" do
      assert SearchQuery.serialize(%SearchQuery{}) == ""
    end

    test "free text only" do
      assert SearchQuery.serialize(%SearchQuery{free_text: "phoenix"}) == "phoenix"
    end

    test "filters serialize in canonical order: free_text, name, description, depends, build_tool, updated_after, extra, unknown" do
      q = %SearchQuery{
        free_text: "phoenix",
        build_tool: "mix",
        depends: "ecto",
        updated_after: "2025-01-01T00:00:00Z",
        extra: [{"license", "MIT"}]
      }

      assert SearchQuery.serialize(q) ==
               "phoenix depends:ecto build_tool:mix updated_after:2025-01-01T00:00:00Z extra:license,MIT"
    end

    test "quotes values containing spaces" do
      q = %SearchQuery{name: "my package"}
      assert SearchQuery.serialize(q) == ~s(name:"my package")
    end

    test "parse ∘ serialize is identity for supported fields" do
      input = "phoenix depends:ecto build_tool:mix extra:license,MIT"
      {:ok, q} = SearchQuery.parse(input)
      assert SearchQuery.serialize(q) == input
    end

    test "unknown keys round-trip" do
      {:ok, q} = SearchQuery.parse("foo:bar build_tool:mix")
      assert SearchQuery.serialize(q) == "build_tool:mix foo:bar"
    end

    test "double quotes inside values are stripped to keep parse symmetric" do
      q = %SearchQuery{name: ~s("hello")}
      serialized = SearchQuery.serialize(q)
      assert serialized == "name:hello"
      refute serialized =~ "\""
      {:ok, parsed} = SearchQuery.parse(serialized)
      assert parsed.name == "hello"
    end

    test "name and description serialize" do
      assert SearchQuery.serialize(%SearchQuery{name: "ecto"}) == "name:ecto"
      assert SearchQuery.serialize(%SearchQuery{description: "auth"}) == "description:auth"
    end

    test "serialize ∘ parse round-trips for structs built directly" do
      q = %SearchQuery{name: "ecto", build_tool: "mix"}
      assert {:ok, ^q} = q |> SearchQuery.serialize() |> SearchQuery.parse()
    end
  end
end
