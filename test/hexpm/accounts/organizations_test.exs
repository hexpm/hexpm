defmodule Hexpm.Accounts.OrganizationsTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.{AuditLogs, Organizations}
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

      assert %{name: "has already been taken"} = errors_on(changeset)
    end
  end

  describe "delete/2" do
    test "refuses to delete the public organization" do
      assert {:error, :public_organization} =
               Organizations.delete(Repo.get!(Hexpm.Accounts.Organization, 1),
                 audit: audit_data(insert(:user))
               )

      assert Repo.get(Hexpm.Accounts.Organization, 1)
    end

    test "publishes org_names.csv without the deleted organization" do
      user = insert(:user)
      organization = insert(:organization)
      kept = insert(:organization)

      assert :ok = Organizations.delete(organization, audit: audit_data(user))

      csv = Hexpm.Store.get(:docs_bucket, "org_names.csv", [])
      refute csv =~ organization.name
      assert csv =~ kept.name
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

  describe "change_visibility/4" do
    test "lists and unlists the member on the public profile" do
      organization = insert(:organization)
      user = insert(:user)
      insert(:organization_user, organization: organization, user: user)

      assert Organizations.public_members(organization) == []
      assert Organizations.public_by_user(user) == []

      assert {:ok, %{public: true}} =
               Organizations.change_visibility(organization, user, %{"public" => "true"},
                 audit: audit_data(user)
               )

      assert [%{id: id}] = Organizations.public_members(organization)
      assert id == user.id
      assert [%{id: organization_id}] = Organizations.public_by_user(user)
      assert organization_id == organization.id

      assert {:ok, %{public: false}} =
               Organizations.change_visibility(organization, user, %{"public" => "false"},
                 audit: audit_data(user)
               )

      assert Organizations.public_members(organization) == []
      assert Organizations.public_by_user(user) == []
    end

    test "audits the change" do
      organization = insert(:organization)
      user = insert(:user)
      insert(:organization_user, organization: organization, user: user)

      {:ok, _organization_user} =
        Organizations.change_visibility(organization, user, %{"public" => "true"},
          audit: audit_data(user)
        )

      assert [audit_log] = AuditLogs.all_by(user)
      assert audit_log.action == "organization.member.visibility"
      assert audit_log.params["public"] == true
      assert audit_log.params["user"]["username"] == user.username
      assert audit_log.params["organization"]["name"] == organization.name
    end

    test "refuses someone who isn't a member" do
      organization = insert(:organization)
      user = insert(:user)

      assert {:error, :not_member} =
               Organizations.change_visibility(organization, user, %{"public" => "true"},
                 audit: audit_data(user)
               )
    end

    test "refuses a value that isn't a boolean" do
      organization = insert(:organization)
      user = insert(:user)
      insert(:organization_user, organization: organization, user: user)

      assert {:error, changeset} =
               Organizations.change_visibility(organization, user, %{"public" => "maybe"},
                 audit: audit_data(user)
               )

      assert errors_on(changeset).public == "expected type boolean"
    end
  end

  describe "public_members/1" do
    test "orders the shown members by username and leaves the others out" do
      organization = insert(:organization)
      zulu = insert(:user, username: "zulu_shown")
      alpha = insert(:user, username: "alpha_shown")
      insert(:organization_user, organization: organization, user: zulu, public: true)
      insert(:organization_user, organization: organization, user: alpha, public: true)
      insert(:organization_user, organization: organization, user: insert(:user))

      other = insert(:organization)
      insert(:organization_user, organization: other, user: insert(:user), public: true)

      assert Enum.map(Organizations.public_members(organization), & &1.username) == [
               "alpha_shown",
               "zulu_shown"
             ]
    end
  end

  describe "public_by_user/1" do
    test "orders public memberships by organization name and leaves other memberships out" do
      user = insert(:user)
      zulu = insert(:organization, name: "zulu_listed")
      alpha = insert(:organization, name: "alpha_listed")
      insert(:organization_user, organization: zulu, user: user, public: true)
      insert(:organization_user, organization: alpha, user: user, public: true)
      insert(:organization_user, organization: insert(:organization), user: user)

      insert(:organization_user,
        organization: insert(:organization),
        user: insert(:user),
        public: true
      )

      assert Enum.map(Organizations.public_by_user(user), & &1.name) == [
               "alpha_listed",
               "zulu_listed"
             ]
    end

    test "returns no organizations for a user without memberships" do
      assert Organizations.public_by_user(insert(:user)) == []
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
