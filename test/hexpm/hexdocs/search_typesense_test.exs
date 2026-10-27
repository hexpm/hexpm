defmodule Hexpm.Hexdocs.Search.TypesenseTest do
  use ExUnit.Case, async: false

  import Mox
  import Hexpm.TestHelpers, only: [capture_final_requests: 1]

  alias Hexpm.Hexdocs.Search.Typesense

  setup :verify_on_exit!

  setup do
    original = %{
      url: Application.get_env(:hexpm, :hexdocs_typesense_url),
      key: Application.get_env(:hexpm, :hexdocs_typesense_api_key),
      collection: Application.get_env(:hexpm, :hexdocs_typesense_collection)
    }

    Application.put_env(:hexpm, :hexdocs_typesense_url, "https://typesense.example")
    Application.put_env(:hexpm, :hexdocs_typesense_api_key, "secret")
    Application.put_env(:hexpm, :hexdocs_typesense_collection, "hexdocs")

    on_exit(fn ->
      restore_env(:hexdocs_typesense_url, original.url)
      restore_env(:hexdocs_typesense_api_key, original.key)
      restore_env(:hexdocs_typesense_collection, original.collection)
    end)

    :ok
  end

  test "indexes normalized search documents as ndjson" do
    items = [
      %{"type" => "module", "ref" => "Example.html", "title" => "Example", "doc" => nil}
    ]

    expect(Hexpm.HTTP.Mock, :post, fn url, headers, body, receive_timeout: 60_000 ->
      assert url ==
               "https://typesense.example/collections/hexdocs/documents/import?action=create"

      assert headers == [{"x-typesense-api-key", "secret"}]

      assert [document] =
               body
               |> IO.iodata_to_binary()
               |> String.split("\n", trim: true)
               |> Enum.map(&JSON.decode!/1)

      assert document == %{
               "type" => "module",
               "ref" => "Example.html",
               "title" => "Example",
               "doc" => "",
               "package" => "package-1.0.0",
               "proglang" => "elixir"
             }

      {:ok, 200, [], ~s({"success":true})}
    end)

    events =
      capture_final_requests(fn ->
        assert :ok = Typesense.index("package", Version.parse!("1.0.0"), "elixir", items)
      end)

    assert events == [%{host: "typesense.example", method: "POST", status: 200}]
  end

  test "normalizes missing, null, and non-string types and documentation" do
    item = %{"ref" => "beam.html#alloc_env", "title" => "beam.alloc_env/0"}

    items = [
      Map.merge(item, %{"type" => nil, "doc" => "Allocates an environment."}),
      Map.merge(item, %{"type" => nil, "doc" => nil}),
      Map.merge(item, %{"type" => 123, "doc" => []}),
      item
    ]

    expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, body, _opts ->
      documents =
        body
        |> IO.iodata_to_binary()
        |> String.split("\n", trim: true)
        |> Enum.map(&JSON.decode!/1)

      expected = %{
        "type" => "",
        "ref" => "beam.html#alloc_env",
        "title" => "beam.alloc_env/0",
        "doc" => "",
        "package" => "zigler-0.17.0",
        "proglang" => "elixir"
      }

      assert documents == [
               Map.put(expected, "doc", "Allocates an environment."),
               expected,
               expected,
               expected
             ]

      {:ok, 200, [], Enum.map_join(items, "\n", fn _ -> ~s({"success":true}) end)}
    end)

    assert :ok = Typesense.index("zigler", "0.17.0", "elixir", items)
  end

  @items [%{"type" => "module", "ref" => "Example.html", "title" => "Example", "doc" => "Doc"}]
  @rejection ~s({"message": "Rejecting write: running out of resource type: OUT_OF_MEMORY"})

  @tag :capture_log
  test "skips null items and items without usable references or titles" do
    first = hd(@items)
    last = %{first | "ref" => "Other.html", "title" => "Other"}

    invalid = [
      nil,
      %{},
      Map.delete(first, "ref"),
      Map.put(first, "ref", nil),
      Map.put(first, "ref", ""),
      Map.put(first, "ref", 123),
      Map.delete(first, "title"),
      Map.put(first, "title", nil),
      Map.put(first, "title", ""),
      Map.put(first, "title", [])
    ]

    data = "searchData=" <> JSON.encode!(%{"items" => [first] ++ invalid ++ [last]})

    assert {"elixir", items} =
             Hexpm.Hexdocs.Search.find_search_items("package", "1.0.0", [
               {"search_data-package.js", data}
             ])

    expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, body, _opts ->
      documents =
        body
        |> IO.iodata_to_binary()
        |> String.split("\n", trim: true)
        |> Enum.map(&JSON.decode!/1)

      assert documents == [
               Map.merge(first, %{"package" => "package-1.0.0", "proglang" => "elixir"}),
               Map.merge(last, %{"package" => "package-1.0.0", "proglang" => "elixir"})
             ]

      {:ok, 200, [], ~s({"success":true}\n{"success":true})}
    end)

    assert :ok = Typesense.index("package", "1.0.0", "elixir", items)
  end

  @tag :capture_log
  test "does not import when there are no usable search items" do
    assert :ok = Typesense.index("package", "1.0.0", "elixir", [])
    assert :ok = Typesense.index("package", "1.0.0", "elixir", [nil, %{}])
  end

  @tag :capture_log
  test "associates import failures with retained items after skipping unusable entries" do
    item = hd(@items)
    last = %{item | "ref" => "Other.html", "title" => "Other"}

    expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, _opts ->
      {:ok, 200, [], ~s({"success":true}\n{"success":false,"error":"rejected"})}
    end)

    assert_raise RuntimeError, ~r/Other\.html.*rejected/, fn ->
      Typesense.index("package", "1.0.0", "elixir", [nil, item, nil, last])
    end
  end

  test "raises WriteRejectedError when Typesense refuses the import" do
    expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, _opts ->
      {:ok, 422, [], @rejection}
    end)

    error =
      assert_raise Hexpm.Hexdocs.Search.WriteRejectedError, fn ->
        Typesense.index("package", "1.0.0", "elixir", @items)
      end

    assert error.message =~ "package 1.0.0"
    assert error.message =~ "OUT_OF_MEMORY"
  end

  test "raises WriteRejectedError when the refusal follows earlier results" do
    expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, _opts ->
      {:ok, 200, [], ~s({"success":true}) <> @rejection}
    end)

    assert_raise Hexpm.Hexdocs.Search.WriteRejectedError, ~r/OUT_OF_MEMORY/, fn ->
      Typesense.index("package", "1.0.0", "elixir", @items)
    end
  end

  test "includes the response body when the import fails" do
    expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, _opts ->
      {:ok, 404, [], ~s({"message": "Not Found"})}
    end)

    assert_raise RuntimeError, ~r/status=404 body=\{"message": "Not Found"\}/, fn ->
      Typesense.index("package", "1.0.0", "elixir", @items)
    end
  end

  test "raises with the line when an import result isn't JSON" do
    expect(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, _opts ->
      {:ok, 200, [], "not json"}
    end)

    assert_raise RuntimeError, ~r/Unexpected import response for package 1.0.0: not json/, fn ->
      Typesense.index("package", "1.0.0", "elixir", @items)
    end
  end

  test "deletes all search documents for a package version" do
    expect(Hexpm.HTTP.Mock, :delete, fn url, headers, receive_timeout: 60_000 ->
      assert url ==
               "https://typesense.example/collections/hexdocs/documents?filter_by=package%3Apackage-1.0.0"

      assert headers == [{"x-typesense-api-key", "secret"}]
      {:ok, 200, [], ""}
    end)

    events =
      capture_final_requests(fn ->
        assert :ok = Typesense.delete("package", Version.parse!("1.0.0"))
      end)

    assert events == [%{host: "typesense.example", method: "DELETE", status: 200}]
  end

  defp restore_env(key, nil), do: Application.delete_env(:hexpm, key)
  defp restore_env(key, value), do: Application.put_env(:hexpm, key, value)
end
