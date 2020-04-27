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

    test "with incorrect params" do
      changeset = ShortURL.changeset(%{foo: 420})
      assert changeset.valid? == false
      assert changeset.errors == [{:url, {"can't be blank", [validation: :required]}}]
    end
  end
end
