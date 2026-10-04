defmodule HexpmWeb.API.OrganizationControllerTest do
  use HexpmWeb.ConnCase, async: true

  alias Hexpm.Accounts.{Key, OrganizationUser}

  defp mock_customer(context) do
    stub(Hexpm.Billing.Mock, :get, fn token, _opts ->
      assert context.organization.name == token
      %{"quantity" => 1}
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

  describe "GET /api/orgs" do
    test "get all organizations authorizes", %{user1: user1} do
      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user1))
        |> get("/api/orgs")

      assert json_response(conn, 200) == []
    end

    test "get all organizations", %{user1: user1, organization: organization} do
      insert(:organization_user, organization: organization, user: user1)

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user1))
        |> get("/api/orgs")

      assert [org] = json_response(conn, 200)
      assert org["name"] == organization.name
    end

    test "sorts organizations by name", %{user1: user1} do
      zulu = insert(:organization, name: "zulu_org")
      alpha = insert(:organization, name: "alpha_org")
      insert(:organization_user, organization: zulu, user: user1)
      insert(:organization_user, organization: alpha, user: user1)

      names =
        build_conn()
        |> put_req_header("authorization", key_for(user1))
        |> get("/api/orgs")
        |> json_response(200)
        |> Enum.map(& &1["name"])

      assert names == ["alpha_org", "zulu_org"]
    end
  end

  describe "GET /api/orgs/:name" do
    setup :mock_customer

    test "get organization authorizes", %{user1: user1, organization: organization} do
      build_conn()
      |> get("/api/orgs/#{organization.name}")
      |> response(404)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get("/api/orgs/#{organization.name}")
      |> response(404)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get("/api/orgs/unknown")
      |> response(404)
    end

    test "get organization", %{user1: user1, organization: organization} do
      insert(:organization_user, organization: organization, user: user1)

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user1))
        |> get("/api/orgs/#{organization.name}")

      org = json_response(conn, 200)
      assert org["name"] == organization.name
    end

    test "organization name is case sensitive", %{user1: user1, organization: organization} do
      insert(:organization_user, organization: organization, user: user1)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get("/api/orgs/#{String.upcase(organization.name)}")
      |> response(404)
    end
  end

  describe "POST /api/orgs/:name" do
    setup :mock_customer
    setup :verify_on_exit!

    test "update organization authorizes", %{user1: user1, organization: organization} do
      build_conn()
      |> post("/api/orgs/#{organization.name}", %{})
      |> response(404)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> post("/api/orgs/#{organization.name}", %{})
      |> response(404)
    end

    test "update organization seats", %{user1: user1, organization: organization} do
      insert(:organization_user, organization: organization, user: user1, role: "admin")

      expect(Hexpm.Billing.Mock, :update, fn token, params ->
        assert organization.name == token
        assert params == %{"quantity" => 5}
        {:ok, %{}}
      end)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> post("/api/orgs/#{organization.name}", %{seats: 5})
      |> response(200)
    end

    test "update organization seats requires admin", %{user1: user1, organization: organization} do
      insert(:organization_user, organization: organization, user: user1, role: "write")

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> post("/api/orgs/#{organization.name}", %{seats: 5})
      |> response(404)
    end

    test "validate update organization seats", %{user1: user1, organization: organization} do
      insert(:organization_user, organization: organization, user: user1, role: "admin")

      result =
        build_conn()
        |> put_req_header("authorization", key_for(user1))
        |> post("/api/orgs/#{organization.name}", %{seats: 0})
        |> json_response(422)

      assert result["errors"] == "number of seats cannot be less than number of members"
    end
  end

  describe "GET /api/orgs/:organization/audit-logs" do
    test "returns 404 when unauthorized", %{user1: user1, organization: organization} do
      build_conn()
      |> get("/api/orgs/#{organization.name}/audit-logs")
      |> response(404)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get("/api/orgs/#{organization.name}/audit-logs")
      |> response(404)
    end

    test "returns the first page of audit_logs related to this organization when params page is not specified",
         %{user1: user1, organization: organization} do
      insert(:organization_user, organization: organization, user: user1, role: "read")
      insert(:audit_log, action: "organization.test", organization: organization)

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user1))
        |> get("/api/orgs/#{organization.name}/audit-logs")

      assert [%{"action" => "organization.test"}] = json_response(conn, :ok)
    end
  end

  describe "read member" do
    setup %{user1: user1, organization: organization} do
      member = insert(:user)
      insert(:organization_user, organization: organization, user: user1, role: "read")
      insert(:organization_user, organization: organization, user: member, role: "write")
      key = insert(:key, organization: organization, name: "existing")
      %{member: member, key: key}
    end

    test "is refused on every route that changes organization state", %{
      user1: user1,
      organization: organization,
      member: member,
      key: key
    } do
      org = "/api/orgs/#{organization.name}"

      requests = [
        {:post, org, %{seats: 10}},
        {:post, "#{org}/members", %{name: insert(:user).username, role: "read"}},
        {:post, "#{org}/members/#{member.username}", %{role: "admin"}},
        {:post, "#{org}/members/#{user1.username}", %{role: "admin"}},
        {:delete, "#{org}/members/#{member.username}", %{}},
        {:post, "#{org}/keys", %{name: "new", permissions: [%{domain: "api"}]}},
        {:delete, "#{org}/keys/#{key.name}", %{}},
        {:delete, "#{org}/keys", %{}}
      ]

      for {method, path, params} <- requests do
        conn =
          build_conn()
          |> put_req_header("authorization", key_for(user1))
          |> dispatch(@endpoint, method, path, params)

        assert conn.status in [403, 404], "#{method} #{path} answered #{conn.status}"
      end

      assert Repo.get_by!(OrganizationUser, organization_id: organization.id, user_id: user1.id).role ==
               "read"

      assert Repo.get_by!(OrganizationUser, organization_id: organization.id, user_id: member.id).role ==
               "write"

      assert Repo.aggregate(
               from(ou in OrganizationUser, where: ou.organization_id == ^organization.id),
               :count
             ) == 2

      assert [%Key{name: "existing", revoke_at: nil}] =
               Repo.all(from(k in Key, where: k.organization_id == ^organization.id))
    end
  end
end
