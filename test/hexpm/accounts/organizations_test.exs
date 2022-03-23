defmodule Hexpm.Accounts.OrganizationsTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.Organizations
  alias Hexpm.Repository.PackageOwner

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
