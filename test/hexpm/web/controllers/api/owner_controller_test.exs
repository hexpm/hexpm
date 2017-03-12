defmodule Hexpm.Web.API.OwnerControllerTest do
  # TODO: debug Bamboo.Test race conditions and change back to async: true
  use Hexpm.ConnCase, async: false
  use Bamboo.Test

  alias Hexpm.Accounts.AuditLog

  setup do
    user1 = insert(:user)
    user2 = insert(:user)
    package = insert(:package, package_owners: [build(:package_owner, owner: user1)])

    %{user1: user1, user2: user2, package: package}
  end

  describe "GET /packages/:name/owners" do
    test "get all package owners", %{user1: user1, user2: user2, package: package} do
      conn = build_conn()
             |> put_req_header("authorization", key_for(user1))
             |> get("api/packages/#{package.name}/owners")

      result = json_response(conn, 200)
      assert List.first(result)["username"] == user1.username

      insert(:package_owner, package: package, owner: user2)

      conn = build_conn()
             |> put_req_header("authorization", key_for(user1))
             |> get("api/packages/#{package.name}/owners")

      [first, second] = json_response(conn, 200)
      assert first["username"] in [user1.username, user2.username]
      assert second["username"] in [user1.username, user2.username]
    end
  end

  describe "GET /packages/:name/owners/:email" do
    test "check if user is package owner", %{user1: user1, user2: user2, package: package} do
      conn = build_conn()
             |> put_req_header("authorization", key_for(user1))
             |> get("api/packages/#{package.name}/owners/#{hd(user1.emails).email}")
      assert conn.status == 204

      conn = build_conn()
             |> put_req_header("authorization", key_for(user1))
             |> get("api/packages/#{package.name}/owners/#{hd(user2.emails).email}")
      assert conn.status == 404

      conn = build_conn()
             |> put_req_header("authorization", key_for(user1))
             |> get("api/packages/#{package.name}/owners/UNKNOWN")
      assert conn.status == 404
    end
  end

  describe "PUT /packages/:name/owners/:email" do
    test "add package owner", %{user1: user1, user2: user2, package: package} do
      conn = build_conn()
             |> put_req_header("authorization", key_for(user1))
             |> put("api/packages/#{package.name}/owners/#{user2.username}")
      assert conn.status == 204

      assert [first, second] = assoc(package, :owners) |> Hexpm.Repo.all
      assert first.username in [user1.username, user2.username]
      assert second.username in [user1.username, user2.username]

      [email] = Bamboo.SentEmail.all
      assert email.subject =~ "Hex.pm"
      assert email.html_body =~ "#{user2.username} has been added as an owner to package #{package.name}."
      emails_first = assoc(first, :emails) |> Hexpm.Repo.all
      emails_second = assoc(second, :emails) |> Hexpm.Repo.all

      assert {first.username, hd(emails_first).email} in email.to
      assert {second.username, hd(emails_second).email} in email.to

      log = Hexpm.Repo.one!(AuditLog)
      assert log.actor_id == user1.id
      assert log.action == "owner.add"
      assert log.params["package"]["name"] == package.name
      assert log.params["user"]["username"] == user2.username
    end

    test "add unknown user package owner", %{user1: user, package: package} do
      conn = build_conn()
             |> put_req_header("authorization", key_for(user))
             |> put("api/packages/#{package.name}/owners/UNKNOWN")
      assert conn.status == 404
    end

    test "can add same owner twice", %{user1: user1, user2: user2, package: package} do
      conn = build_conn()
             |> put_req_header("authorization", key_for(user1))
             |> put("api/packages/#{package.name}/owners/#{hd(user2.emails).email}")
      assert conn.status == 204

      conn = build_conn()
             |> put_req_header("authorization", key_for(user1))
             |> put("api/packages/#{package.name}/owners/#{hd(user2.emails).email}")
      assert conn.status == 204
    end

    test "add package owner authorizes", %{user2: user2, package: package} do
      user3 = insert(:user)

      conn = build_conn()
             |> put_req_header("authorization", key_for(user3))
             |> put("api/packages/#{package.name}/owners/#{hd(user2.emails).email}")
      assert conn.status == 403
    end
  end


  describe "DELETE /packages/:name/owners/:email" do
    test "delete package owner", %{user1: user1, user2: user2, package: package} do
      insert(:package_owner, package: package, owner: user2)

      conn = build_conn()
             |> put_req_header("authorization", key_for(user1))
             |> delete("api/packages/#{package.name}/owners/#{user2.username}")
      assert conn.status == 204
      assert [user] = assoc(package, :owners) |> Hexpm.Repo.all
      assert user.id == user1.id

      [email] = Bamboo.SentEmail.all
      assert email.subject =~ "Hex.pm"
      assert email.html_body =~ "#{user2.username} has been removed from owners of package #{package.name}."

      user1_emails = assoc(user1, :emails) |> Hexpm.Repo.all
      user2_emails = assoc(user2, :emails) |> Hexpm.Repo.all

      assert {user1.username, hd(user1_emails).email} in email.to
      assert {user2.username, hd(user2_emails).email} in email.to

      log = Hexpm.Repo.one!(AuditLog)
      assert log.actor_id == user1.id
      assert log.action == "owner.remove"
      assert log.params["package"]["name"] == package.name
      assert log.params["user"]["username"] == user2.username
    end

    test "delete package owner authorizes", %{user1: user1, user2: user2, package: package} do
      conn = build_conn()
             |> put_req_header("authorization", key_for(user2))
             |> delete("api/packages/#{package.name}/owners/#{user1.username}")
      assert conn.status == 403
    end

    test "delete unknown user package owner", %{user1: user1, user2: user2, package: package} do
      insert(:package_owner, package: package, owner: user2)

      conn = build_conn()
             |> put_req_header("authorization", key_for(user1))
             |> delete("api/packages/#{package.name}/owners/UNKNOWN")
      assert conn.status == 404
    end

    test "not possible to remove last owner of package", %{user1: user1, package: package} do
      conn = build_conn()
             |> put_req_header("authorization", key_for(user1))
             |> delete("api/packages/#{package.name}/owners/#{user1.username}")
      assert conn.status == 403
      assert [user] = assoc(package, :owners) |> Hexpm.Repo.all
      assert user.id == user1.id
    end
  end
end
