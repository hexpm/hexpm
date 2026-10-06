defmodule Hexpm.Repository.OwnersTest do
  use Hexpm.DataCase, async: true

  import Swoosh.TestAssertions

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
end
