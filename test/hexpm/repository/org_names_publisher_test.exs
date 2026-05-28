defmodule Hexpm.Repository.OrgNamesPublisherTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Repository.OrgNamesPublisher

  defp published_csv do
    Hexpm.Store.get(:docs_bucket, "org_names.csv", [])
  end

  test "publishes an empty file when there are no organizations" do
    assert :ok = OrgNamesPublisher.publish()
    assert published_csv() == ""
  end

  test "writes one org name per line, sorted alphabetically" do
    insert(:organization, name: "zorro")
    insert(:organization, name: "acme")
    insert(:organization, name: "myorg")

    assert :ok = OrgNamesPublisher.publish()
    assert published_csv() == "acme\nmyorg\nzorro"
  end

  test "excludes the public 'hexpm' organization (seeded into every test DB)" do
    insert(:organization, name: "acme")

    assert :ok = OrgNamesPublisher.publish()
    assert published_csv() == "acme"
  end
end
