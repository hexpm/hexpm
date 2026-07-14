defmodule Hexpm.Hexdocs.Search.TypesenseTest do
  use ExUnit.Case, async: false

  import Mox

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
               |> Enum.map(&Jason.decode!/1)

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

    assert :ok = Typesense.index("package", Version.parse!("1.0.0"), "elixir", items)
  end

  test "deletes all search documents for a package version" do
    expect(Hexpm.HTTP.Mock, :delete, fn url, headers, receive_timeout: 60_000 ->
      assert url ==
               "https://typesense.example/collections/hexdocs/documents?filter_by=package%3Apackage-1.0.0"

      assert headers == [{"x-typesense-api-key", "secret"}]
      {:ok, 200, [], ""}
    end)

    assert :ok = Typesense.delete("package", Version.parse!("1.0.0"))
  end

  defp restore_env(key, nil), do: Application.delete_env(:hexpm, key)
  defp restore_env(key, value), do: Application.put_env(:hexpm, key, value)
end
