defmodule Hexpm.ShortURLs.ShortURLTest do
  use Hexpm.DataCase, async: true
  alias Hexpm.ShortURLs.{ShortURL, Target}

  describe "canonical_diff_url/1" do
    test "sorts comparisons" do
      assert {:ok, url, packages} =
               ShortURL.canonical_diff_url(
                 "https://hex.pm/diffs?diffs[]=plug:1.0.0:1.1.0&diffs[]=ecto:3.0.0:3.0.1"
               )

      assert url == "https://hex.pm/diffs?diffs[]=ecto:3.0.0:3.0.1&diffs[]=plug:1.0.0:1.1.0"
      assert packages == ["ecto", "plug"]
    end

    test "sorts comparisons of the same package by version" do
      assert {:ok, url, packages} =
               ShortURL.canonical_diff_url(
                 "https://hex.pm/diffs?diffs[]=ecto:3.1.0:3.2.0&diffs[]=ecto:3.0.0:3.0.1"
               )

      assert url == "https://hex.pm/diffs?diffs[]=ecto:3.0.0:3.0.1&diffs[]=ecto:3.1.0:3.2.0"
      assert packages == ["ecto"]
    end

    test "drops duplicate comparisons" do
      assert {:ok, url, _packages} =
               ShortURL.canonical_diff_url(
                 "https://hex.pm/diffs?diffs[]=ecto:3.0.0:3.0.1&diffs[]=ecto:3.0.0:3.0.1"
               )

      assert url == "https://hex.pm/diffs?diffs[]=ecto:3.0.0:3.0.1"
    end

    test "gives links on diff.hex.pm and hex.pm the same canonical form" do
      canonical = "https://hex.pm/diffs?diffs[]=ecto:3.0.0:3.0.1&diffs[]=plug:1.0.0:1.1.0"

      for url <- [
            "https://diff.hex.pm/diffs?diffs[]=plug:1.0.0:1.1.0&diffs[]=ecto:3.0.0:3.0.1",
            "https://diff.hex.pm?diff[]=ecto:3.0.0:3.0.1&diff[]=plug:1.0.0:1.1.0",
            "https://diff.hex.pm/?diffs[]=ecto:3.0.0:3.0.1&diffs[]=plug:1.0.0:1.1.0",
            "http://hex.pm/diffs?diffs[]=ecto:3.0.0:3.0.1&diffs[]=plug:1.0.0:1.1.0",
            "https://hex.pm/diffs?diffs[]=ecto:3.0.0:3.0.1&diffs[]=plug:1.0.0:1.1.0"
          ] do
        assert {:ok, ^canonical, _packages} = ShortURL.canonical_diff_url(url)
      end
    end

    test "decodes percent-encoding and re-encodes only what the query needs" do
      assert {:ok, url, _packages} =
               ShortURL.canonical_diff_url(
                 "https://hex.pm/diffs?diffs%5B%5D=ecto%3A3.0.0-rc.1%2Bbuild.1%3A3.0.1"
               )

      assert url == "https://hex.pm/diffs?diffs[]=ecto:3.0.0-rc.1%2Bbuild.1:3.0.1"

      %URI{query: query} = URI.parse(url)
      assert Plug.Conn.Query.decode(query) == %{"diffs" => ["ecto:3.0.0-rc.1+build.1:3.0.1"]}
    end

    test "drops other query parameters and the fragment" do
      assert {:ok, "https://hex.pm/diffs?diffs[]=ecto:3.0.0:3.0.1", _packages} =
               ShortURL.canonical_diff_url(
                 "https://hex.pm/diffs?diffs[]=ecto:3.0.0:3.0.1&utm_source=x#top"
               )
    end

    test "accepts 150 comparisons" do
      assert {:ok, _url, _packages} = ShortURL.canonical_diff_url(diff_url(150))
    end

    test "rejects more than 150 comparisons" do
      assert ShortURL.canonical_diff_url(diff_url(151)) ==
               {:error, "must contain at most 150 comparisons"}
    end

    test "rejects a comparison longer than 512 bytes" do
      version = "1.0.0-" <> String.duplicate("a", 512)

      assert ShortURL.canonical_diff_url("https://hex.pm/diffs?diffs[]=ecto:#{version}:1.0.1") ==
               {:error, "has an invalid comparison"}
    end

    test "rejects a link without a query" do
      assert ShortURL.canonical_diff_url("https://hex.pm/diffs") ==
               {:error, "must contain at least one comparison"}
    end

    for url <- [
          "https://hex.pm/packages/ecto",
          "https://hex.pm/?diffs[]=ecto:3.0.0:3.0.1",
          "https://hexdocs.pm/?diffs[]=ecto:3.0.0:3.0.1",
          "https://evil.example/diffs?diffs[]=ecto:3.0.0:3.0.1",
          "https://preview.hex.pm/diffs?diffs[]=ecto:3.0.0:3.0.1",
          "https://user@hex.pm/diffs?diffs[]=ecto:3.0.0:3.0.1",
          "https://hex.pm:8443/diffs?diffs[]=ecto:3.0.0:3.0.1",
          "javascript://hex.pm/diffs?diffs[]=ecto:3.0.0:3.0.1",
          "https://hex.pm/diffs?diffs[]=ecto:3.0.0:3.0.1\n"
        ] do
      test "rejects #{inspect(url)}" do
        assert {:error, _reason} = ShortURL.canonical_diff_url(unquote(url))
      end
    end

    for {label, query} <- [
          {"no comparisons", "foo=bar"},
          {"an organization package", "diffs[]=acme/ecto:3.0.0:3.0.1"},
          {"an invalid package name", "diffs[]=Ecto:3.0.0:3.0.1"},
          {"a package name longer than 255 bytes",
           "diffs[]=#{String.duplicate("a", 256)}:1.0.0:1.0.1"},
          {"an invalid from version", "diffs[]=ecto:3.0:3.0.1"},
          {"an invalid to version", "diffs[]=ecto:3.0.0:latest"},
          {"a missing version", "diffs[]=ecto:3.0.0"},
          {"one invalid comparison among valid ones",
           "diffs[]=ecto:3.0.0:3.0.1&diffs[]=plug:1.0:1.1.0"},
          {"a comparison map", "diffs[a]=ecto:3.0.0:3.0.1"},
          {"invalid percent-encoding", "diffs[]=ecto%ZZ:3.0.0:3.0.1"}
        ] do
      test "rejects #{label}" do
        assert {:error, _reason} =
                 ShortURL.canonical_diff_url("https://hex.pm/diffs?" <> unquote(query))
      end
    end
  end

  describe "diff_changeset/1" do
    test "puts the canonical url and the package names" do
      changeset =
        ShortURL.diff_changeset(%{
          "url" => "https://diff.hex.pm/diffs?diffs[]=plug:1.0.0:1.1.0&diffs[]=ecto:3.0.0:3.0.1"
        })

      assert changeset.valid?

      assert changeset.changes.url ==
               "https://hex.pm/diffs?diffs[]=ecto:3.0.0:3.0.1&diffs[]=plug:1.0.0:1.1.0"

      assert changeset.changes.packages == ["ecto", "plug"]
    end

    test "requires a url" do
      assert %{valid?: false, errors: errors} = ShortURL.diff_changeset(%{foo: 420})
      assert errors == [{:url, {"can't be blank", [validation: :required]}}]
    end

    test "rejects a link that is not a diff link" do
      changeset = ShortURL.diff_changeset(%{"url" => "https://hexdocs.pm"})
      assert errors_on(changeset).url == "must be a hex.pm diff link"
    end
  end

  describe "redirect_url/1" do
    test "reads the target" do
      short_url = %ShortURL{
        url: "https://diff.hex.pm/diffs?diffs[]=ecto:3.0.0:3.0.1",
        target: %Target{url: "https://hex.pm/diffs?diffs[]=ecto:3.0.0:3.0.1"}
      }

      assert ShortURL.redirect_url(short_url) == "https://hex.pm/diffs?diffs[]=ecto:3.0.0:3.0.1"
    end

    test "reads the url when there is no target" do
      short_url = %ShortURL{url: "https://diff.hex.pm/diff/ecto/3.0.1..3.0.4"}

      assert ShortURL.redirect_url(short_url) == "https://diff.hex.pm/diff/ecto/3.0.1..3.0.4"
    end

    test "keeps redirecting to hex.pm and hexdocs.pm pages" do
      for url <- [
            "https://hex.pm/packages/ecto",
            "https://hexdocs.pm/",
            "https://acme.hexorgs.pm/"
          ] do
        assert ShortURL.redirect_url(%ShortURL{target: %Target{url: url}}) == url
      end
    end

    for url <- [
          "https://evil.example\\@hex.pm/",
          "https://evil.example/",
          "https://hexdocs.pm/foo",
          "javascript://hex.pm/%0Aalert(1)"
        ] do
      test "refuses a stored #{inspect(url)}" do
        refute ShortURL.redirect_url(%ShortURL{target: %Target{url: unquote(url)}})
        refute ShortURL.redirect_url(%ShortURL{url: unquote(url)})
      end
    end
  end

  defp diff_url(count) do
    query = Enum.map_join(1..count, "&", &"diffs[]=ecto:1.0.#{&1}:2.0.0")
    "https://hex.pm/diffs?" <> query
  end
end
