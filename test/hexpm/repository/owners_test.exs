defmodule Hexpm.Repository.OwnersTest do
  use Hexpm.DataCase, async: true

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
  end
end
