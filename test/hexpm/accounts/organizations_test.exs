defmodule Hexpm.Accounts.OrganizationsTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.Organizations
  alias Hexpm.Repository.PackageOwner

  describe "create/3" do
    test "publishes org_names.csv to the docs bucket" do
      user = insert(:user)

      params = %{
        "name" => "acmecorp_#{System.unique_integer([:positive])}"
      }

      assert {:ok, organization} =
               Organizations.create(user, params, audit: audit_data(user))

      csv = Hexpm.Store.get(:docs_bucket, "org_names.csv", [])
      assert csv =~ organization.name
      refute csv =~ "hexpm\n"
      refute String.starts_with?(csv, "hexpm")
    end

    test "rejects reserved package names" do
      user = insert(:user)

      for name <- ~w(elixir mix kernel api docs phoenix acme) do
        assert {:error, %{errors: [name: {"is reserved", _}]}} =
                 Organizations.create(user, %{"name" => name}, audit: audit_data(user))
      end
    end
  end

  describe "create/3 with reserved username" do
    test "rejects an organization name in reserved_usernames" do
      Repo.insert!(%Hexpm.Accounts.ReservedUsername{name: "graveyard"})
      user = insert(:user)

      assert {:error, changeset} =
               Organizations.create(user, %{"name" => "graveyard"}, audit: audit_data(user))

      assert %{username: "has already been taken"} = errors_on(changeset)
    end
  end

  describe "remove_member/3" do
    test "cannot remove last member" do
      user = insert(:user)
      organization = insert(:organization)
      insert(:organization_user, organization: organization, user: user)

      assert Organizations.remove_member(organization, user, audit: audit_data(build(:user))) ==
               {:error, :last_member}

      assert length(Repo.all(assoc(organization, :users))) == 1
    end

    test "removes member" do
      user = insert(:user)
      organization = insert(:organization)
      insert(:organization_user, organization: organization, user: insert(:user))
      insert(:organization_user, organization: organization, user: user)

      assert Organizations.remove_member(organization, user, audit: audit_data(build(:user)))
      assert length(Repo.all(assoc(organization, :users))) == 1
    end

    test "removes package ownerships" do
      user = insert(:user)
      repository = insert(:repository)
      organization = insert(:organization, repository: repository)
      package = insert(:package, repository_id: repository.id, repository: repository)
      package_owner = insert(:package_owner, package: package, user: user)
      insert(:organization_user, organization: organization, user: insert(:user))
      insert(:organization_user, organization: organization, user: user)

      assert Organizations.remove_member(organization, user, audit: audit_data(build(:user)))
      refute Repo.get(PackageOwner, package_owner.id)
    end
  end
end
