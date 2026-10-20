defmodule Hexpm.Repository.OwnersTest do
  use Hexpm.DataCase, async: true

  import Swoosh.TestAssertions

  alias Hexpm.Accounts.User
  alias Hexpm.Repository.Owners

  setup do
    owner = insert(:user)

    package =
      insert(:package, package_owners: [build(:package_owner, user: owner, level: "full")])
      |> Repo.preload(repository: :organization)

    %{owner: owner, package: package}
  end

  describe "add/4" do
    test "adds a user with a verified primary email", %{owner: owner, package: package} do
      user = insert(:user)

      assert {:ok, package_owner} = Owners.add(package, user, %{}, audit: audit_data(owner))
      assert package_owner.user_id == user.id
      assert Owners.get(package, user).level == "full"
    end

    test "refuses a user whose primary email is unverified", %{owner: owner, package: package} do
      user = insert(:user, emails: [build(:email, verified: false)])

      assert {:error, :unverified_primary_email} =
               Owners.add(package, user, %{}, audit: audit_data(owner))

      refute Owners.get(package, user)
    end

    test "refuses a transfer to a user whose primary email is unverified", %{
      owner: owner,
      package: package
    } do
      user = insert(:user, emails: [build(:email, verified: false)])

      assert {:error, :unverified_primary_email} =
               Owners.add(package, user, %{"transfer" => true}, audit: audit_data(owner))

      assert [%{user_id: owner_id}] = Owners.all(package)
      assert owner_id == owner.id
    end

    test "a verified secondary email does not stand in for the primary", %{
      owner: owner,
      package: package
    } do
      user =
        insert(:user,
          emails: [
            build(:email, verified: false),
            build(:email, primary: false, public: false, gravatar: false)
          ]
        )

      assert {:error, :unverified_primary_email} =
               Owners.add(package, user, %{}, audit: audit_data(owner))
    end

    test "transfers to an organization without consulting its emails", %{
      owner: owner,
      package: package
    } do
      name = Fake.sequence(:package)

      organization =
        insert(:organization, name: name, user: build(:user, username: name, emails: []))

      organization_user = Repo.preload(organization.user, [:emails, :organization])

      assert {:ok, package_owner} =
               Owners.add(package, organization_user, %{"transfer" => true},
                 audit: audit_data(owner)
               )

      assert package_owner.user_id == organization.user.id
      assert [%{user_id: user_id}] = Owners.all(package)
      assert user_id == organization.user.id
    end

    test "a transfer removes the package's workload identities", %{
      owner: owner,
      package: package
    } do
      workload_identity = insert(:workload_identity, package: package)
      other_package_identity = insert(:workload_identity)
      new_owner = insert(:user)

      token =
        Repo.insert!(%Hexpm.OAuth.Token{
          jti: "transfer-jti",
          token_type: "bearer",
          scopes: ["package:hexpm/#{package.name}"],
          expires_at: DateTime.utc_now() |> DateTime.add(600) |> DateTime.truncate(:second),
          grant_type: "workload_identity",
          grant_reference: "oidc-transfer-jti",
          workload_identity_id: workload_identity.id
        })

      assert {:ok, _} =
               Owners.add(package, new_owner, %{"transfer" => true}, audit: audit_data(owner))

      refute Repo.get(Hexpm.WorkloadIdentities.WorkloadIdentity, workload_identity.id)
      assert Repo.get(Hexpm.WorkloadIdentities.WorkloadIdentity, other_package_identity.id)
      assert Repo.get!(Hexpm.OAuth.Token, token.id).revoked_at

      log = Repo.get_by!(Hexpm.Accounts.AuditLog, action: "workload_identity.remove")
      assert log.params["repository"] == workload_identity.repository
      assert log.params["package"]["name"] == package.name
    end

    test "a transfer to an organization lists its workload identities that start publishing to its admins only",
         %{owner: owner, package: package} do
      admin = insert(:user)

      organization =
        insert(:organization,
          organization_users: [build(:organization_user, user: admin, role: "admin")]
        )

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repository: "acme/widget",
        workflow: "release.yml",
        covers_public: true
      )

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repository: "acme/gadget",
        workflow: "listed.yml",
        covers_public: true,
        public_packages: [package.name]
      )

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repository: "acme/other",
        workflow: "other.yml",
        covers_public: true,
        public_packages: ["other_package"]
      )

      organization_user =
        Repo.preload(organization.user, [:emails, organization: [organization_users: :user]])

      assert {:ok, _} =
               Owners.add(package, organization_user, %{"transfer" => true},
                 audit: audit_data(owner)
               )

      assert_email_sent(fn email ->
        refute email.text_body =~ "acme/other"
        assert Enum.map(email.to, &elem(&1, 1)) == [User.email(admin, :primary)]
        assert email.subject =~ "Owner added to package #{package.name}"
        assert email.text_body =~ "These workload identities of your organization now publish"
        assert email.text_body =~ "acme/widget (release.yml), organization #{organization.name}"
        assert email.text_body =~ "acme/gadget (listed.yml), organization #{organization.name}"
      end)

      assert_email_sent(fn email ->
        refute email.text_body =~ "acme/"
        assert Enum.map(email.to, &elem(&1, 1)) == [User.email(owner, :primary)]
        assert email.subject =~ "Owner added to package #{package.name}"
      end)

      refute_email_sent()
    end

    test "a transfer away from an organization doesn't show its workload identities to anyone",
         %{owner: owner, package: package} do
      organization = insert(:organization)
      insert(:package_owner, package: package, user: organization.user, level: "full")

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repository: "acme/widget",
        workflow: "release.yml",
        covers_public: true
      )

      new_owner = insert(:user)

      assert {:ok, _} =
               Owners.add(package, new_owner, %{"transfer" => true}, audit: audit_data(owner))

      assert_email_sent(fn email ->
        refute email.text_body =~ "acme/widget"

        assert User.email(new_owner, :primary) in Enum.map(email.to, &elem(&1, 1))
      end)

      refute_email_sent()
    end

    test "adding an owner keeps the package's workload identities", %{
      owner: owner,
      package: package
    } do
      workload_identity = insert(:workload_identity, package: package)

      assert {:ok, _} = Owners.add(package, insert(:user), %{}, audit: audit_data(owner))
      assert Repo.get(Hexpm.WorkloadIdentities.WorkloadIdentity, workload_identity.id)
    end
  end

  describe "remove/3" do
    test "tells the owners which workload identities can still publish", %{
      owner: owner,
      package: package
    } do
      removed = insert(:user)
      insert(:package_owner, package: package, user: removed)

      insert(:workload_identity,
        package: package,
        repository: "acme/widget",
        workflow: "release.yml"
      )

      assert :ok = Owners.remove(package, removed, audit: audit_data(owner))

      assert_email_sent(fn email ->
        assert email.subject =~ "Owner removed from package #{package.name}"

        assert email.text_body =~
                 "Removing an owner doesn't change #{package.name}'s workload identities"

        assert email.text_body =~ "acme/widget (release.yml)"
        assert email.text_body =~ "/packages/#{package.name}/workload-identities"
      end)
    end

    test "removing an organization lists its workload identities that stop publishing", %{
      owner: owner,
      package: package
    } do
      organization = insert(:organization)
      insert(:package_owner, package: package, user: organization.user, level: "full")

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repository: "acme/widget",
        workflow: "release.yml",
        covers_public: true
      )

      insert(:workload_identity, package: package, repository: "acme/own", workflow: "own.yml")

      assert :ok = Owners.remove(package, organization.user, audit: audit_data(owner))

      assert Hexpm.WorkloadIdentities.list_covering(package) == []

      assert_email_sent(fn email ->
        assert email.text_body =~
                 "These workload identities of organization #{organization.name} no longer publish #{package.name}"

        assert email.text_body =~ "acme/widget (release.yml)"
        assert email.text_body =~ "acme/own (own.yml)"
      end)
    end

    test "removing a person leaves the organization's workload identities out", %{
      owner: owner,
      package: package
    } do
      organization = insert(:organization)
      insert(:package_owner, package: package, user: organization.user, level: "full")
      removed = insert(:user)
      insert(:package_owner, package: package, user: removed)

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repository: "acme/widget",
        workflow: "release.yml",
        covers_public: true
      )

      assert :ok = Owners.remove(package, removed, audit: audit_data(owner))

      assert_email_sent(fn email ->
        refute email.text_body =~ "acme/widget"
        assert email.subject =~ "Owner removed"
      end)
    end

    test "says nothing about workload identities when there are none", %{
      owner: owner,
      package: package
    } do
      removed = insert(:user)
      insert(:package_owner, package: package, user: removed)

      assert :ok = Owners.remove(package, removed, audit: audit_data(owner))

      assert_email_sent(fn email ->
        refute email.text_body =~ "workload identities"
        assert email.subject =~ "Owner removed"
      end)
    end
  end

  describe "the acting owner" do
    test "is checked again once the package is locked", %{owner: owner, package: package} do
      maintainer = insert(:user)
      insert(:package_owner, package: package, user: maintainer, level: "maintainer")
      audit = audit_data(maintainer)

      assert {:error, :not_full_owner} =
               Owners.add(package, insert(:user), %{"transfer" => true}, audit: audit)

      assert {:error, :not_full_owner} =
               Owners.update_level(package, owner, "maintainer", audit: audit)

      assert {:error, :not_full_owner} = Owners.remove(package, owner, audit: audit)

      assert Enum.map(Owners.all(package), &{&1.user_id, &1.level}) |> Enum.sort() ==
               Enum.sort([{owner.id, "full"}, {maintainer.id, "maintainer"}])
    end

    test "can be an organization that owns the package" do
      organization = insert(:organization)

      package =
        insert(:package,
          package_owners: [build(:package_owner, user: organization.user, level: "full")]
        )
        |> Repo.preload(repository: :organization)

      audit = %{audit_data(insert(:user)) | user: organization}

      assert {:ok, _} = Owners.add(package, insert(:user), %{}, audit: audit)

      other_package =
        insert(:package, package_owners: [build(:package_owner, user: insert(:user))])
        |> Repo.preload(repository: :organization)

      assert {:error, :not_full_owner} =
               Owners.add(other_package, insert(:user), %{}, audit: audit)
    end
  end
end
