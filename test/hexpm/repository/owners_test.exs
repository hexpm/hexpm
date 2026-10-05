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

    test "a transfer removes the package's trusted publishers", %{
      owner: owner,
      package: package
    } do
      trusted_publisher = insert(:trusted_publisher, package: package)
      other_package_publisher = insert(:trusted_publisher)
      new_owner = insert(:user)

      assert {:ok, _} =
               Owners.add(package, new_owner, %{"transfer" => true}, audit: audit_data(owner))

      refute Repo.get(Hexpm.TrustedPublishers.TrustedPublisher, trusted_publisher.id)
      assert Repo.get(Hexpm.TrustedPublishers.TrustedPublisher, other_package_publisher.id)

      log = Repo.get_by!(Hexpm.Accounts.AuditLog, action: "trusted_publisher.remove")
      assert log.params["repository"] == trusted_publisher.repository
      assert log.params["package"]["name"] == package.name
    end

    test "adding an owner keeps the package's trusted publishers", %{
      owner: owner,
      package: package
    } do
      trusted_publisher = insert(:trusted_publisher, package: package)

      assert {:ok, _} = Owners.add(package, insert(:user), %{}, audit: audit_data(owner))
      assert Repo.get(Hexpm.TrustedPublishers.TrustedPublisher, trusted_publisher.id)
    end
  end

  describe "remove/3" do
    test "tells the owners which trusted publishers can still publish", %{
      owner: owner,
      package: package
    } do
      removed = insert(:user)
      insert(:package_owner, package: package, user: removed)

      insert(:trusted_publisher,
        package: package,
        repository: "acme/widget",
        workflow: "release.yml"
      )

      assert :ok = Owners.remove(package, removed, audit: audit_data(owner))

      assert_email_sent(fn email ->
        assert email.subject =~ "Owner removed from package #{package.name}"

        assert email.text_body =~
                 "Removing an owner doesn't change #{package.name}'s trusted publishers"

        assert email.text_body =~ "acme/widget (release.yml)"
        assert email.text_body =~ "/packages/#{package.name}/trusted-publishers"
      end)
    end

    test "says nothing about trusted publishers when there are none", %{
      owner: owner,
      package: package
    } do
      removed = insert(:user)
      insert(:package_owner, package: package, user: removed)

      assert :ok = Owners.remove(package, removed, audit: audit_data(owner))

      assert_email_sent(fn email ->
        refute email.text_body =~ "trusted publishers"
        assert email.subject =~ "Owner removed"
      end)
    end
  end
end
