defmodule HexpmWeb.API.OwnerControllerTest do
  use HexpmWeb.ConnCase, async: true
  use Bamboo.Test

  alias Hexpm.Accounts.AuditLog
  alias Hexpm.Repository.{Owners, PackageOwner}

  setup do
    user1 = insert(:user)
    user2 = insert(:user)
    organization = insert(:organization)
    package = insert(:package, package_owners: [build(:package_owner, user: user1)])

    organization_package =
      insert(
        :package,
        organization_id: organization.id,
        package_owners: [build(:package_owner, user: user1)]
      )

    %{
      user1: user1,
      user2: user2,
      organization: organization,
      package: package,
      organization_package: organization_package
    }
  end

  describe "GET /packages/:name/owners" do
    test "get all package owners", %{user1: user1, user2: user2, package: package} do
      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user1))
        |> get("api/packages/#{package.name}/owners")

      result = json_response(conn, 200)
      assert List.first(result)["username"] == user1.username

      insert(:package_owner, package: package, user: user2)

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user1))
        |> get("api/packages/#{package.name}/owners")

      [first, second] = json_response(conn, 200)
      assert first["username"] in [user1.username, user2.username]
      assert second["username"] in [user1.username, user2.username]
    end
  end

  describe "GET /repos/:organization/packages/:name/owners" do
    test "returns 403 if you are not authorized", %{
      user1: user1,
      organization: organization,
      organization_package: package
    } do
      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get("api/repos/#{organization.name}/packages/#{package.name}/owners")
      |> json_response(403)
    end

    test "returns 403 for unknown organization", %{
      user1: user1,
      organization: organization,
      organization_package: package
    } do
      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get("api/repos/UNKNOWN_REPOSITORY/packages/#{package.name}/owners")
      |> json_response(403)

      build_conn()
      |> put_req_header("authorization", key_for(organization))
      |> get("api/repos/UNKNOWN_REPOSITORY/packages/#{package.name}/owners")
      |> json_response(403)
    end

    test "returns 403 for missing package if you are not authorized", %{
      user1: user1,
      organization: organization
    } do
      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get("api/repos/#{organization.name}/packages/UNKNOWN_PACKAGE/owners")
      |> json_response(403)

      other_organization = insert(:organization)

      build_conn()
      |> put_req_header("authorization", key_for(other_organization))
      |> get("api/repos/#{organization.name}/packages/UNKNOWN_PACKAGE/owners")
      |> json_response(403)
    end

    test "returns 404 for missing package if you are authorized", %{
      user1: user1,
      organization: organization
    } do
      insert(:organization_user, organization: organization, user: user1)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get("api/repos/#{organization.name}/packages/UNKNOWN_PACKAGE/owners")
      |> json_response(404)

      build_conn()
      |> put_req_header("authorization", key_for(organization))
      |> get("api/repos/#{organization.name}/packages/UNKNOWN_PACKAGE/owners")
      |> json_response(404)
    end

    test "get all package owners", %{
      user1: user1,
      organization: organization,
      organization_package: package
    } do
      insert(:organization_user, organization: organization, user: user1)

      result =
        build_conn()
        |> put_req_header("authorization", key_for(user1))
        |> get("api/repos/#{organization.name}/packages/#{package.name}/owners")
        |> json_response(200)

      assert List.first(result)["username"] == user1.username
    end

    test "get all package owners for organization key", %{
      user1: user1,
      organization: organization,
      organization_package: package
    } do
      insert(:organization_user, organization: organization, user: user1)

      result =
        build_conn()
        |> put_req_header("authorization", key_for(organization))
        |> get("api/repos/#{organization.name}/packages/#{package.name}/owners")
        |> json_response(200)

      assert List.first(result)["username"] == user1.username
    end
  end

  describe "GET /packages/:name/owners/:email" do
    test "check if user is package owner", %{user1: user1, user2: user2, package: package} do
      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get("api/packages/#{package.name}/owners/#{hd(user1.emails).email}")
      |> response(200)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get("api/packages/#{package.name}/owners/#{hd(user2.emails).email}")
      |> response(404)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get("api/packages/#{package.name}/owners/UNKNOWN")
      |> response(404)
    end
  end

  describe "GET /repos/:organization/packages/:name/owners/:email" do
    test "returns 403 if you are not authorized", %{
      user1: user1,
      organization: organization,
      organization_package: package
    } do
      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get(
        "api/repos/#{organization.name}/packages/#{package.name}/owners/#{hd(user1.emails).email}"
      )
      |> response(403)
    end

    test "returns 403 for unknown organization", %{user1: user1, organization_package: package} do
      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get(
        "api/repos/UNKNOWN_REPOSITORY/packages/#{package.name}/owners/#{hd(user1.emails).email}"
      )
      |> response(403)
    end

    test "returns 403 for missing package if you are not authorized", %{
      user1: user1,
      organization: organization
    } do
      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get(
        "api/repos/#{organization.name}/packages/UNKNOWN_PACKAGE/owners/#{hd(user1.emails).email}"
      )
      |> response(403)
    end

    test "returns 404 for missing package if you are authorized", %{
      user1: user1,
      organization: organization
    } do
      insert(:organization_user, organization: organization, user: user1)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get(
        "api/repos/#{organization.name}/packages/UNKNOWN_PACKAGE/owners/#{hd(user1.emails).email}"
      )
      |> response(404)
    end

    test "check if user is package owner", %{
      user1: user1,
      organization: organization,
      organization_package: package
    } do
      insert(:organization_user, organization: organization, user: user1)
      email = hd(user1.emails).email

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get("api/repos/#{organization.name}/packages/#{package.name}/owners/#{email}")
      |> response(200)
    end
  end

  describe "PUT /packages/:name/owners/:email" do
    test "add full package owner", %{user1: user1, user2: user2, package: package} do
      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> put("api/packages/#{package.name}/owners/#{user2.username}")
      |> response(204)

      assert [first, second] = assoc(package, :owners) |> Hexpm.Repo.all()
      assert first.username in [user1.username, user2.username]
      assert second.username in [user1.username, user2.username]
      assert Owners.get(package, user2).level == "full"

      recipients = Enum.sort([user1, user2])
      assert_delivered_email(Hexpm.Emails.owner_added(package, recipients, user2))

      log = Hexpm.Repo.one!(AuditLog)
      assert log.user_id == user1.id
      assert log.action == "owner.add"
      assert log.params["package"]["name"] == package.name
      assert log.params["user"]["username"] == user2.username
    end

    test "add maintainer package owner", %{user1: user1, user2: user2, package: package} do
      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> put("api/packages/#{package.name}/owners/#{user2.username}", %{level: "maintainer"})
      |> response(204)

      assert Owners.get(package, user2).level == "maintainer"
    end

    test "cannot add package owner with maintainer level", %{user2: user2, package: package} do
      insert(:package_owner, package: package, user: user2, level: "maintainer")
      user3 = insert(:user)

      build_conn()
      |> put_req_header("authorization", key_for(user2))
      |> put("api/packages/#{package.name}/owners/#{user3.username}")
      |> response(403)
    end

    test "add unknown user package owner", %{user1: user, package: package} do
      build_conn()
      |> put_req_header("authorization", key_for(user))
      |> put("api/packages/#{package.name}/owners/UNKNOWN")
      |> response(404)
    end

    test "can add same owner twice", %{user1: user1, user2: user2, package: package} do
      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> put("api/packages/#{package.name}/owners/#{hd(user2.emails).email}")
      |> response(204)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> put("api/packages/#{package.name}/owners/#{hd(user2.emails).email}")
      |> response(204)
    end

    test "add package owner authorizes", %{user2: user2, package: package} do
      user3 = insert(:user)

      build_conn()
      |> put_req_header("authorization", key_for(user3))
      |> put("api/packages/#{package.name}/owners/#{hd(user2.emails).email}")
      |> response(403)
    end
  end

  describe "PUT /repos/:organization/packages/:name/owners/:email" do
    test "returns 403 if you are not authorized", %{
      user1: user1,
      user2: user2,
      organization: organization,
      organization_package: package
    } do
      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> put("api/repos/#{organization.name}/packages/#{package.name}/owners/#{user2.username}")
      |> response(403)

      assert Hexpm.Repo.aggregate(assoc(package, :owners), :count, :id) == 1
    end

    test "returns 403 for unknown organization", %{
      user1: user1,
      user2: user2,
      organization_package: package
    } do
      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> put("api/repos/UNKNOWN_REPOSITORY/packages/#{package.name}/owners/#{user2.username}")
      |> response(403)

      assert Hexpm.Repo.aggregate(assoc(package, :owners), :count, :id) == 1
    end

    test "returns 403 for missing package if you are not authorized", %{
      user1: user1,
      user2: user2,
      organization: organization,
      organization_package: package
    } do
      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> put("api/repos/#{organization.name}/packages/UNKNOWN_PACKAGE/owners/#{user2.username}")
      |> response(403)

      assert Hexpm.Repo.aggregate(assoc(package, :owners), :count, :id) == 1
    end

    test "returns 403 if organization does not have active billing", %{user1: user1, user2: user2} do
      organization = insert(:organization, billing_active: false)
      insert(:organization_user, organization: organization, user: user1)
      insert(:organization_user, organization: organization, user: user2)

      package =
        insert(
          :package,
          organization_id: organization.id,
          package_owners: [build(:package_owner, user: user1)]
        )

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> put("api/repos/#{organization.name}/packages/#{package.name}/owners/#{user2.username}")
      |> response(403)

      assert Hexpm.Repo.aggregate(assoc(package, :owners), :count, :id) == 1
    end

    test "returns 404 for missing package if you are authorized", %{
      user1: user1,
      user2: user2,
      organization: organization,
      organization_package: package
    } do
      insert(:organization_user, organization: organization, user: user1, role: "admin")
      insert(:organization_user, organization: organization, user: user2)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> put("api/repos/#{organization.name}/packages/UNKNOWN_PACKAGE/owners/#{user2.username}")
      |> response(404)

      assert Hexpm.Repo.aggregate(assoc(package, :owners), :count, :id) == 1
    end

    test "requries owner to be member of organization", %{
      user1: user1,
      organization: organization,
      organization_package: package
    } do
      insert(:organization_user, organization: organization, user: user1)
      user3 = insert(:user)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> put("api/repos/#{organization.name}/packages/#{package.name}/owners/#{user3.username}")
      |> response(422)

      assert Hexpm.Repo.aggregate(assoc(package, :owners), :count, :id) == 1
    end

    test "add package owner", %{
      user1: user1,
      user2: user2,
      organization: organization,
      organization_package: package
    } do
      insert(:organization_user, organization: organization, user: user1)
      insert(:organization_user, organization: organization, user: user2)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> put("api/repos/#{organization.name}/packages/#{package.name}/owners/#{user2.username}")
      |> response(204)

      assert Hexpm.Repo.aggregate(assoc(package, :owners), :count, :id) == 2
    end

    test "add package owner using admin permission and without package owner", %{
      user2: user2,
      organization: organization,
      organization_package: package
    } do
      insert(:organization_user, organization: organization, user: user2, role: "admin")
      user3 = insert(:user)
      insert(:organization_user, organization: organization, user: user3)

      build_conn()
      |> put_req_header("authorization", key_for(user2))
      |> put("api/repos/#{organization.name}/packages/#{package.name}/owners/#{user3.username}")
      |> response(204)

      assert Hexpm.Repo.aggregate(assoc(package, :owners), :count, :id) == 2
    end
  end

  describe "DELETE /packages/:name/owners/:email" do
    test "delete package owner", %{user1: user1, user2: user2, package: package} do
      insert(:package_owner, package: package, user: user2)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> delete("api/packages/#{package.name}/owners/#{user2.username}")
      |> response(204)

      assert [user] = assoc(package, :owners) |> Hexpm.Repo.all()
      assert user.id == user1.id

      recipients = Enum.sort([user1, user2])
      assert_delivered_email(Hexpm.Emails.owner_removed(package, recipients, user2))

      log = Hexpm.Repo.one!(AuditLog)
      assert log.user_id == user1.id
      assert log.action == "owner.remove"
      assert log.params["package"]["name"] == package.name
      assert log.params["user"]["username"] == user2.username
    end

    test "delete package owner authorizes", %{user1: user1, user2: user2, package: package} do
      build_conn()
      |> put_req_header("authorization", key_for(user2))
      |> delete("api/packages/#{package.name}/owners/#{user1.username}")
      |> response(403)
    end

    test "delete unknown user package owner", %{user1: user1, user2: user2, package: package} do
      insert(:package_owner, package: package, user: user2)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> delete("api/packages/#{package.name}/owners/UNKNOWN")
      |> response(404)
    end

    test "not possible to remove last owner of package", %{user1: user1, package: package} do
      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> delete("api/packages/#{package.name}/owners/#{user1.username}")
      |> json_response(422)

      assert [user] = assoc(package, :owners) |> Hexpm.Repo.all()
      assert user.id == user1.id
    end
  end

  describe "DELETE /repos/:organization/packages/:name/owners/:email" do
    test "returns 403 if you are not authorized", %{
      user1: user1,
      user2: user2,
      organization: organization,
      organization_package: package
    } do
      insert(:package_owner, package: package, user: user2)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> delete(
        "api/repos/#{organization.name}/packages/#{package.name}/owners/#{user2.username}"
      )
      |> response(403)

      assert Hexpm.Repo.aggregate(assoc(package, :owners), :count, :id) == 2
    end

    test "returns 403 for unknown organization", %{
      user1: user1,
      user2: user2,
      organization_package: package
    } do
      insert(:package_owner, package: package, user: user2)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> delete("api/repos/UNKNOWN_REPOSITORY/packages/#{package.name}/owners/#{user2.username}")
      |> response(403)

      assert Hexpm.Repo.aggregate(assoc(package, :owners), :count, :id) == 2
    end

    test "returns 403 for missing package if you are not authorized", %{
      user1: user1,
      user2: user2,
      organization: organization,
      organization_package: package
    } do
      insert(:package_owner, package: package, user: user2)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> delete(
        "api/repos/#{organization.name}/packages/UNKNOWN_PACKAGE/owners/#{user2.username}"
      )
      |> response(403)

      assert Hexpm.Repo.aggregate(assoc(package, :owners), :count, :id) == 2
    end

    test "returns 404 for missing package if you are authorized", %{
      user1: user1,
      user2: user2,
      organization: organization,
      organization_package: package
    } do
      insert(:organization_user, organization: organization, user: user1, role: "admin")
      insert(:package_owner, package: package, user: user2)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> delete(
        "api/repos/#{organization.name}/packages/UNKNOWN_PACKAGE/owners/#{user2.username}"
      )
      |> response(404)

      assert Hexpm.Repo.aggregate(assoc(package, :owners), :count, :id) == 2
    end

    test "delete package owner", %{
      user1: user1,
      user2: user2,
      organization: organization,
      organization_package: package
    } do
      insert(:organization_user, organization: organization, user: user1)
      insert(:package_owner, package: package, user: user2)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> delete(
        "api/repos/#{organization.name}/packages/#{package.name}/owners/#{user2.username}"
      )
      |> response(204)

      assert Hexpm.Repo.aggregate(assoc(package, :owners), :count, :id) == 1
    end

    test "delete package owner using write permission and without package owner", %{
      user1: user1,
      user2: user2,
      organization: organization,
      organization_package: package
    } do
      insert(:organization_user, organization: organization, user: user1, role: "admin")
      Repo.delete_all(from(po in PackageOwner, where: po.user_id == ^user1.id))
      insert(:package_owner, package: package, user: user2)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> delete(
        "api/repos/#{organization.name}/packages/#{package.name}/owners/#{user2.username}"
      )
      |> response(204)

      assert Hexpm.Repo.aggregate(assoc(package, :owners), :count, :id) == 0
    end
  end
end
