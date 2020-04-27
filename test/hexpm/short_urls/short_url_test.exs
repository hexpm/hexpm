defmodule Hexpm.ShortURLs.ShortURLTest do
  use Hexpm.DataCase, async: true
  alias Hexpm.ShortURLs.ShortURL

  describe "changeset/1" do
    test "with correct params, creates a new short url" do
      params = %{"url" => "https://diff.hex.pm?diff[]=ecto:3.0.1:3.0.4"}
      %{valid?: valid?, changes: changes} = ShortURL.changeset(params)
      assert valid? == true
      assert String.length(changes.short_code) == 5
    end

    test "valid when redirecting to hex.pm" do
      params = %{"url" => "https://hex.pm"}
      %{valid?: valid?} = ShortURL.changeset(params)
      assert valid? == true
    end

    test "valid when redirecting to a complex subdomain on hex.pm" do
      params = %{"url" => "https://www.links.hex.pm"}
      %{valid?: valid?} = ShortURL.changeset(params)
      assert valid? == true
    end

    test "with incorrect params" do
      changeset = ShortURL.changeset(%{foo: 420})
      assert changeset.valid? == false
      assert changeset.errors == [{:url, {"can't be blank", [validation: :required]}}]
    end

    test "where host is not on hex.pm" do
      changeset = ShortURL.changeset(%{url: "https://supersimple.org?spoof=hex.pm"})
      assert changeset.valid? == false
      assert changeset.errors == [url: {"domain must match hex.pm or *.hex.pm", []}]
    end
  end
end
