defmodule Hexpm.Accounts.OrganizationTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.Organization

  describe "changeset/2 name validation" do
    test "accepts underscores" do
      assert Organization.changeset(%Organization{}, %{name: "foo_bar"}).valid?
    end

    test "accepts plain alphanumeric names" do
      assert Organization.changeset(%Organization{}, %{name: "globex"}).valid?
    end

    test "rejects hyphens" do
      refute Organization.changeset(%Organization{}, %{name: "foo-bar"}).valid?
    end

    test "rejects dots" do
      refute Organization.changeset(%Organization{}, %{name: "foo.bar"}).valid?
    end
  end
end
