defmodule HexpmWeb.API.OrganizationUserControllerTest do
  use HexpmWeb.ConnCase, async: true
  alias Hexpm.Accounts.Organizations

  defp mock_customer(context) do
    Mox.stub(Hexpm.Billing.Mock, :get, fn token ->
      assert context.organization.name == token
      %{"quantity" => 2}
    end)

    context
  end

  setup do
    user1 = insert(:user)
    organization = insert(:organization)

    %{
      user1: user1,
      organization: organization
    }
  end

  describe "GET /api/orgs/:organization/users" do
    test "get all organization members authorizes", %{user1: user1, organization: organization} do
      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get("api/orgs/#{organization.name}/users")
      |> response(403)
    end

    test "get all organization members", %{user1: user1, organization: organization} do
      insert(:organization_user, organization: organization, user: user1)

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user1))
        |> get("api/orgs/#{organization.name}/users")

      assert [user] = json_response(conn, 200)
      assert user["username"] == user1.username
      assert user["role"] == "read"
    end
  end

  describe "POST /api/orgs/:organization/users" do
    setup :mock_customer

    test "new organization member authorizes", %{user1: user1, organization: organization} do
      user2 = insert(:user)
      params = %{"name" => user2.username, "role" => "read"}

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> post("api/orgs/#{organization.name}/users", params)
      |> response(403)

      refute Organizations.get_role(organization, user2)

      insert(:organization_user, organization: organization, user: user1, role: "write")

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> post("api/orgs/#{organization.name}/users", params)
      |> response(403)

      refute Organizations.get_role(organization, user2)
    end

    test "new organization member validates number of seats", %{
      user1: user1,
      organization: organization
    } do
      user2 = insert(:user)
      user3 = insert(:user)
      insert(:organization_user, organization: organization, user: user1, role: "admin")
      insert(:organization_user, organization: organization, user: user2)
      params = %{"name" => user3.username, "role" => "read"}

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user1))
        |> post("api/orgs/#{organization.name}/users", params)

      result = json_response(conn, 422)
      assert result["errors"] == "not enough seats to add member"
      refute Organizations.get_role(organization, user3)
    end

    test "new organization member validates already member", %{
      user1: user1,
      organization: organization
    } do
      insert(:organization_user, organization: organization, user: user1, role: "admin")
      params = %{"name" => user1.username, "role" => "read"}

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user1))
        |> post("api/orgs/#{organization.name}/users", params)

      result = json_response(conn, 422)
      assert result["errors"]["user_id"] == "is already member"
    end

    test "new organization member", %{user1: user1, organization: organization} do
      user2 = insert(:user)
      insert(:organization_user, organization: organization, user: user1, role: "admin")
      params = %{"name" => user2.username, "role" => "read"}

      user =
        build_conn()
        |> put_req_header("authorization", key_for(user1))
        |> post("api/orgs/#{organization.name}/users", params)
        |> json_response(200)

      assert user["username"] == user2.username
      assert user["role"] == "read"
      assert Organizations.get_role(organization, user2) == "read"
    end
  end

  describe "GET /api/orgs/:organization/users/:name" do
    test "get organization member authorizes", %{user1: user1, organization: organization} do
      user2 = insert(:user)
      insert(:organization_user, organization: organization, user: user2)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get("api/orgs/#{organization.name}/users/#{user2.username}")
      |> response(403)
    end

    test "get organization member", %{user1: user1, organization: organization} do
      insert(:organization_user, organization: organization, user: user1)

      user =
        build_conn()
        |> put_req_header("authorization", key_for(user1))
        |> get("api/orgs/#{organization.name}/users/#{user1.username}")
        |> json_response(200)

      assert user["username"] == user1.username
      assert user["role"] == "read"
    end
  end

  describe "POST /api/orgs/:organization/users/:name" do
    test "update organization member authorizes", %{user1: user1, organization: organization} do
      user2 = insert(:user)
      insert(:organization_user, organization: organization, user: user2)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> post("api/orgs/#{organization.name}/users/#{user2.username}", %{role: "write"})
      |> response(403)

      assert Organizations.get_role(organization, user2) == "read"

      insert(:organization_user, organization: organization, user: user1, role: "write")

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> post("api/orgs/#{organization.name}/users/#{user2.username}", %{role: "write"})
      |> response(403)

      assert Organizations.get_role(organization, user2) == "read"
    end

    test "update organization member validates demote last admin", %{
      user1: user1,
      organization: organization
    } do
      insert(:organization_user, organization: organization, user: user1, role: "admin")

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user1))
        |> post("api/orgs/#{organization.name}/users/#{user1.username}", %{role: "write"})

      result = json_response(conn, 422)
      assert result["errors"] == "cannot demote last admin member"
      assert Organizations.get_role(organization, user1) == "admin"
    end

    test "update organization member", %{user1: user1, organization: organization} do
      user2 = insert(:user)
      insert(:organization_user, organization: organization, user: user1, role: "admin")
      insert(:organization_user, organization: organization, user: user2, role: "read")

      user =
        build_conn()
        |> put_req_header("authorization", key_for(user1))
        |> post("api/orgs/#{organization.name}/users/#{user2.username}", %{role: "write"})
        |> json_response(200)

      assert user["username"] == user2.username
      assert user["role"] == "write"
      assert Organizations.get_role(organization, user2) == "write"
    end
  end

  describe "DELETE /api/orgs/:organization/users/:name" do
    test "delete organization member authorizes", %{user1: user1, organization: organization} do
      user2 = insert(:user)
      insert(:organization_user, organization: organization, user: user2)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> delete("api/orgs/#{organization.name}/users/#{user2.username}")
      |> response(403)

      assert Organizations.get_role(organization, user2) == "read"

      insert(:organization_user, organization: organization, user: user1, role: "write")

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> delete("api/orgs/#{organization.name}/users/#{user2.username}")
      |> response(403)

      assert Organizations.get_role(organization, user2) == "read"
    end

    test "delete organization member validates remove last member", %{
      user1: user1,
      organization: organization
    } do
      insert(:organization_user, organization: organization, user: user1, role: "admin")

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user1))
        |> delete("api/orgs/#{organization.name}/users/#{user1.username}")

      result = json_response(conn, 422)
      assert result["errors"] == "cannot remove last member"
      assert Organizations.get_role(organization, user1) == "admin"
    end

    test "delete organization member", %{user1: user1, organization: organization} do
      user2 = insert(:user)
      insert(:organization_user, organization: organization, user: user1, role: "admin")
      insert(:organization_user, organization: organization, user: user2, role: "read")

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> delete("api/orgs/#{organization.name}/users/#{user2.username}")
      |> response(204)

      refute Organizations.get_role(organization, user2)
    end
  end
end
