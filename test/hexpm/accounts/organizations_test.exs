defmodule Hexpm.Accounts.OrganizationsTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.Organizations
  alias Hexpm.Repository.PackageOwner

  describe "all_admin_notifiable_emails/1" do
    test "returns the verified primary address of each admin once" do
      admin = insert(:user)
      member = insert(:user)
      organization = insert(:organization)
      other = insert(:organization)
      insert(:organization_user, organization: organization, user: admin, role: "admin")
      insert(:organization_user, organization: other, user: admin, role: "admin")
      insert(:organization_user, organization: organization, user: member, role: "write")

      assert Organizations.all_admin_notifiable_emails() == [hd(admin.emails).email]
    end

    test "skips unverified addresses and deactivated admins" do
      organization = insert(:organization)
      unverified = insert(:user, emails: [build(:email, verified: false)])
      deactivated = insert(:user, deactivated_at: DateTime.utc_now())
      insert(:organization_user, organization: organization, user: unverified, role: "admin")
      insert(:organization_user, organization: organization, user: deactivated, role: "admin")

      assert Organizations.all_admin_notifiable_emails() == []
    end

    test "filters on billing_active" do
      billed = insert(:user)
      unbilled = insert(:user)
      billed_org = insert(:organization, billing_active: true)
      unbilled_org = insert(:organization, billing_active: false)
      insert(:organization_user, organization: billed_org, user: billed, role: "admin")
      insert(:organization_user, organization: unbilled_org, user: unbilled, role: "admin")

      assert Organizations.all_admin_notifiable_emails(billing_active: true) ==
               [hd(billed.emails).email]

      assert Organizations.all_admin_notifiable_emails(billing_active: false) ==
               [hd(unbilled.emails).email]
    end
  end

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

    test "rejects reserved organization names" do
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

  describe "add_member/4" do
    setup do
      organization = insert(:organization)
      admin = insert(:user)
      insert(:organization_user, organization: organization, user: admin, role: "admin")
      %{organization: organization, admin: admin}
    end

    test "adds a user with a verified primary email", %{organization: organization, admin: admin} do
      user = insert(:user)

      assert {:ok, organization_user} =
               Organizations.add_member(organization, user, %{"role" => "write"},
                 audit: audit_data(admin)
               )

      assert organization_user.role == "write"
      assert Organizations.get_role(organization, user) == "write"
    end

    test "refuses a user whose primary email is unverified", %{
      organization: organization,
      admin: admin
    } do
      user = insert(:user, emails: [build(:email, verified: false)])

      assert {:error, :unverified_primary_email} =
               Organizations.add_member(organization, user, %{"role" => "write"},
                 audit: audit_data(admin)
               )

      refute Organizations.get_role(organization, user)
    end

    test "a verified secondary email does not stand in for the primary", %{
      organization: organization,
      admin: admin
    } do
      user =
        insert(:user,
          emails: [
            build(:email, verified: false),
            build(:email, primary: false, public: false, gravatar: false)
          ]
        )

      assert {:error, :unverified_primary_email} =
               Organizations.add_member(organization, user, %{"role" => "read"},
                 audit: audit_data(admin)
               )
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
