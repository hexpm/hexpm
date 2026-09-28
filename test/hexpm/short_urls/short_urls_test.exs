defmodule Hexpm.ShortURLsTest do
  use Hexpm.DataCase, async: true
  alias Hexpm.ShortURLs
  alias Hexpm.ShortURLs.{ShortURL, Target}

  setup do
    [first, second] = Enum.sort_by([insert(:package), insert(:package)], & &1.name)
    %{first: first.name, second: second.name}
  end

  describe "add/2" do
    test "stores the canonical url", %{first: first, second: second} do
      url =
        "https://diff.hex.pm/diffs?diffs[]=#{second}:1.0.0:1.1.0&diffs[]=#{first}:2.0.0:2.0.1"

      assert {:ok, short_url} = ShortURLs.add(%{"url" => url})
      assert String.length(short_url.short_code) == 5

      canonical =
        "https://hex.pm/diffs?diffs[]=#{first}:2.0.0:2.0.1&diffs[]=#{second}:1.0.0:1.1.0"

      assert from(s in "short_urls", where: s.id == ^short_url.id, select: s.url) |> Repo.one() ==
               nil

      short_url = ShortURLs.get(short_url.short_code)
      assert short_url.target.url == canonical
      assert short_url.target.url_hash == Target.url_hash(canonical)
      assert ShortURL.redirect_url(short_url) == canonical
    end

    test "returns the existing short url for the same set of comparisons", %{
      first: first,
      second: second
    } do
      assert {:ok, short_url} =
               ShortURLs.add(%{
                 "url" =>
                   "https://diff.hex.pm/diffs?diffs[]=#{second}:1.0.0:1.1.0&diffs[]=#{first}:2.0.0:2.0.1"
               })

      for url <- [
            "https://hex.pm/diffs?diffs[]=#{first}:2.0.0:2.0.1&diffs[]=#{second}:1.0.0:1.1.0",
            "https://hex.pm/diffs?diffs[]=#{second}:1.0.0:1.1.0&diffs[]=#{first}:2.0.0:2.0.1&diffs[]=#{first}:2.0.0:2.0.1"
          ] do
        assert {:ok, again} = ShortURLs.add(%{"url" => url})
        assert again.id == short_url.id
        assert again.short_code == short_url.short_code
      end

      assert Repo.aggregate(ShortURL, :count) == 1
      assert Repo.aggregate(Target, :count) == 1
    end

    test "calls before_insert only when a new row would be written", %{first: first} do
      url = "https://hex.pm/diffs?diffs[]=#{first}:1.0.0:1.1.0"

      before_insert = fn ->
        send(self(), :before_insert)
        :ok
      end

      assert {:ok, short_url} = ShortURLs.add(%{"url" => url}, before_insert: before_insert)
      assert_received :before_insert

      assert {:ok, again} = ShortURLs.add(%{"url" => url}, before_insert: before_insert)
      assert again.id == short_url.id
      refute_received :before_insert
    end

    test "writes nothing when before_insert refuses", %{first: first} do
      url = "https://hex.pm/diffs?diffs[]=#{first}:1.0.0:1.1.0"

      assert ShortURLs.add(%{"url" => url}, before_insert: fn -> :refused end) ==
               {:error, :refused}

      assert Repo.aggregate(ShortURL, :count) == 0
      assert Repo.aggregate(Target, :count) == 0
    end

    test "rejects a comparison of a package that does not exist", %{first: first} do
      url =
        "https://hex.pm/diffs?diffs[]=#{first}:1.0.0:1.1.0&diffs[]=not_a_package:1.0.0:1.1.0"

      assert {:error, changeset} = ShortURLs.add(%{"url" => url})
      assert errors_on(changeset).url == "unknown packages: not_a_package"
      assert Repo.aggregate(ShortURL, :count) == 0
    end

    test "rejects a package that only exists in an organization repository" do
      repository = insert(:repository)
      package = insert(:package, repository_id: repository.id)
      url = "https://hex.pm/diffs?diffs[]=#{package.name}:1.0.0:1.1.0"

      assert {:error, changeset} = ShortURLs.add(%{"url" => url})
      assert errors_on(changeset).url == "unknown packages: #{package.name}"
    end

    test "rejects a url that is not a diff link" do
      assert {:error, changeset} = ShortURLs.add(%{"url" => "https://hex.pm/packages/ecto"})
      assert errors_on(changeset).url == "must be a hex.pm diff link"
    end

    # `URI.parse/1` ends the authority at the first "/", "?" or "#", a browser
    # also ends it at a "\\" and drops tabs and newlines first, and both split
    # userinfo at the "@". Every spelling that reads as one host here and
    # another one there is refused rather than reconciled.
    for {label, url} <- [
          {"backslash before the allowed host", "https://evil.example\\@hex.pm/diffs"},
          {"encoded backslash", "https://evil.example%5c@hex.pm/diffs"},
          {"tab", "https://evil.example\t@hex.pm/diffs"},
          {"carriage return", "https://evil.example\r@hex.pm/diffs"},
          {"space", "https://evil.example @hex.pm/diffs"},
          {"userinfo", "https://user@hex.pm/diffs"},
          {"encoded separator in the host", "https://evil.com%2f.hex.pm/diffs"},
          {"IPv6 literal as userinfo", "https://[::1]@hex.pm/diffs"},
          {"allowed host as userinfo", "https://hex.pm@evil.com/diffs"},
          {"non-default port", "https://hex.pm:8443/diffs"},
          {"tab inside the port", "https://hex.pm:443\t0/diffs"},
          {"newline inside the host", "https://hex\n.pm/diffs"}
        ] do
      test "refuses a URL with a #{label}", %{first: first} do
        url = unquote(url) <> "?diffs[]=#{first}:1.0.0:1.1.0"
        assert {:error, %{valid?: false}} = ShortURLs.add(%{"url" => url})
      end
    end
  end

  describe "get/1" do
    test "given a short_code that exists, returns a record with its target" do
      target = insert_target("https://hex.pm/diffs?diffs[]=ecto:3.0.1:3.0.4")
      Repo.insert!(%ShortURL{short_code: "abcde", target_id: target.id})

      assert %ShortURL{target: %Target{url: "https://hex.pm/diffs?diffs[]=ecto:3.0.1:3.0.4"}} =
               ShortURLs.get("abcde")
    end

    test "reads the url of a short code without a target" do
      Repo.insert_all("short_urls", [
        %{
          short_code: "fghjk",
          url: "https://diff.hex.pm/diffs?diffs[]=ecto:3.0.1:3.0.4",
          inserted_at: NaiveDateTime.utc_now()
        }
      ])

      short_url = ShortURLs.get("fghjk")
      refute short_url.target
      assert short_url.url == "https://diff.hex.pm/diffs?diffs[]=ecto:3.0.1:3.0.4"

      assert ShortURL.redirect_url(short_url) ==
               "https://diff.hex.pm/diffs?diffs[]=ecto:3.0.1:3.0.4"
    end

    test "given a short_code that does not exist, returns nil" do
      refute ShortURLs.get("zyxwv")
    end
  end

  defp insert_target(url) do
    Repo.insert!(%Target{url: url, url_hash: Target.url_hash(url)})
  end
end
