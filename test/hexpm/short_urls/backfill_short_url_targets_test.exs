defmodule Hexpm.Repo.Migrations.BackfillShortURLTargetsTest do
  use Hexpm.DataCase, async: true
  alias Hexpm.ShortURLs
  alias Hexpm.ShortURLs.{ShortURL, Target}
  alias Hexpm.Repo.Migrations.BackfillShortURLTargets, as: Migration

  unless Code.ensure_loaded?(Migration) do
    Code.require_file("priv/repo/migrations/20260928120100_backfill_short_url_targets.exs")
  end

  setup do
    [first, second] = Enum.sort_by([insert(:package), insert(:package)], & &1.name)
    %{first: first.name, second: second.name}
  end

  describe "backfill/2" do
    test "merges rows with the same canonical url and keeps every short code resolving", %{
      first: first,
      second: second
    } do
      canonical =
        "https://hex.pm/diffs?diffs[]=#{first}:2.0.0:2.0.1&diffs[]=#{second}:1.0.0:1.1.0"

      rows = [
        {"aaaaa",
         "https://diff.hex.pm/diffs?diffs[]=#{second}:1.0.0:1.1.0&diffs[]=#{first}:2.0.0:2.0.1"},
        {"bbbbb",
         "https://diff.hex.pm/diffs?diffs[]=#{first}:2.0.0:2.0.1&diffs[]=#{second}:1.0.0:1.1.0"},
        {"ccccc",
         "https://diff.hex.pm/diffs?diffs[]=#{first}:2.0.0:2.0.1&diffs[]=#{second}:1.0.0:1.1.0"},
        {"ddddd", canonical},
        {"eeeee", "https://diff.hex.pm/diffs?diffs[]=#{first}:1.0.0:1.0.1"},
        {"fffff", "https://hexdocs.pm/"},
        {"ggggg", "https://hex.pm/packages/ecto"},
        {"hhhhh", "https://evil.example\\@hex.pm/"},
        {"iiiii", "https://diff.hex.pm/diffs?diffs[]=#{first}:1.0:1.0.1"}
      ]

      for {code, url} <- rows, do: insert_untargeted(code, url)

      assert Migration.backfill(Hexpm.RepoBase, batch_size: 2) == :ok

      short_urls = Map.new(rows, fn {code, _url} -> {code, ShortURLs.get(code)} end)
      assert Enum.all?(Map.values(short_urls), & &1.target_id)

      for code <- ~w(aaaaa bbbbb ccccc ddddd) do
        assert short_urls[code].target_id == short_urls["aaaaa"].target_id
        assert ShortURL.redirect_url(short_urls[code]) == canonical
      end

      assert ShortURL.redirect_url(short_urls["eeeee"]) ==
               "https://hex.pm/diffs?diffs[]=#{first}:1.0.0:1.0.1"

      assert ShortURL.redirect_url(short_urls["fffff"]) == "https://hexdocs.pm/"
      assert ShortURL.redirect_url(short_urls["ggggg"]) == "https://hex.pm/packages/ecto"
      refute ShortURL.redirect_url(short_urls["hhhhh"])

      assert short_urls["iiiii"].target.url ==
               "https://diff.hex.pm/diffs?diffs[]=#{first}:1.0:1.0.1"

      assert Repo.aggregate(Target, :count) == 6

      assert {:ok, %ShortURL{short_code: "aaaaa"}} = ShortURLs.add(%{"url" => canonical})
    end

    test "reuses an existing target and leaves rows that have one alone", %{first: first} do
      url = "https://hex.pm/diffs?diffs[]=#{first}:1.0.0:1.1.0"
      assert {:ok, existing} = ShortURLs.add(%{"url" => url})

      insert_untargeted("legcy", "https://diff.hex.pm/diffs?diffs[]=#{first}:1.0.0:1.1.0")

      assert Migration.backfill(Hexpm.RepoBase) == :ok
      assert Migration.backfill(Hexpm.RepoBase) == :ok

      assert ShortURLs.get("legcy").target_id == existing.target_id
      assert ShortURLs.get(existing.short_code).target_id == existing.target_id
      assert Repo.aggregate(Target, :count) == 1
    end
  end

  defp insert_untargeted(short_code, url) do
    Repo.insert_all("short_urls", [
      %{short_code: short_code, url: url, inserted_at: NaiveDateTime.utc_now()}
    ])
  end
end
