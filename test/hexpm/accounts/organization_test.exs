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

    test "bounds the name in bytes" do
      assert Organization.changeset(%Organization{}, %{name: String.duplicate("a", 255)}).valid?

      changeset = Organization.changeset(%Organization{}, %{name: String.duplicate("a", 256)})
      assert errors_on(changeset).name == "should be at most 255 byte(s)"
    end
  end
end
