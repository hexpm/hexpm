defmodule Hexpm.ShortURLs.ShortURLTest do
  use Hexpm.DataCase, async: true
  alias Hexpm.ShortURLs.ShortURL

  describe "changeset/1" do
    test "with correct params, creates a new short url" do
      params = %{"url" => "https://diff.hex.pm?diff[]=ecto:3.0.1:3.0.4"}
      assert %{valid?: true, changes: changes} = ShortURL.changeset(params)
      assert String.length(changes.short_code) == 5
    end

    test "valid when redirecting to hex.pm" do
      params = %{"url" => "https://hex.pm"}
      assert %{valid?: true} = ShortURL.changeset(params)
    end

    test "valid when redirecting to a complex subdomain on hex.pm" do
      params = %{"url" => "https://www.links.hex.pm"}
      assert %{valid?: true} = ShortURL.changeset(params)
    end

    test "with incorrect params" do
      assert %{valid?: false, errors: errors} = ShortURL.changeset(%{foo: 420})
      assert errors == [{:url, {"can't be blank", [validation: :required]}}]
    end

    test "where host is not on hex.pm" do
      assert %{valid?: false, errors: errors} =
               ShortURL.changeset(%{url: "https://supersimple.org?spoof=hex.pm"})

      assert errors == [url: {"domain must match hex.pm or *.hex.pm", []}]
    end
  end
end
