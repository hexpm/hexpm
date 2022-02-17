defmodule HexpmWeb.API.OrganizationControllerTest do
  use HexpmWeb.ConnCase, async: true

  defp mock_customer(context) do
    Mox.stub(Hexpm.Billing.Mock, :get, fn token ->
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
        |> get("api/orgs")

      assert json_response(conn, 200) == []
    end

    test "get all organizations", %{user1: user1, organization: organization} do
      insert(:organization_user, organization: organization, user: user1)

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user1))
        |> get("api/orgs")

      assert [org] = json_response(conn, 200)
      assert org["name"] == organization.name
    end
  end

  describe "GET /api/orgs/:name" do
    setup :mock_customer

    test "get organization authorizes", %{user1: user1, organization: organization} do
      build_conn()
      |> get("api/orgs/#{organization.name}")
      |> response(404)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get("api/orgs/#{organization.name}")
      |> response(404)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get("api/orgs/unknown")
      |> response(404)
    end

    test "get organization", %{user1: user1, organization: organization} do
      insert(:organization_user, organization: organization, user: user1)

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user1))
        |> get("api/orgs/#{organization.name}")

      org = json_response(conn, 200)
      assert org["name"] == organization.name
    end

    test "organization name is case sensitive", %{user1: user1, organization: organization} do
      insert(:organization_user, organization: organization, user: user1)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get("api/orgs/#{String.upcase(organization.name)}")
      |> response(404)
    end
  end

  describe "POST /api/orgs/:name" do
    setup :mock_customer

    test "update organization authorizes", %{user1: user1, organization: organization} do
      build_conn()
      |> post("api/orgs/#{organization.name}", %{})
      |> response(404)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> post("api/orgs/#{organization.name}", %{})
      |> response(404)
    end

    test "update organization seats", %{user1: user1, organization: organization} do
      insert(:organization_user, organization: organization, user: user1, role: "write")

      Mox.expect(Hexpm.Billing.Mock, :update, fn token, params ->
        assert organization.name == token
        assert params == %{"quantity" => 5}
        {:ok, %{}}
      end)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> post("api/orgs/#{organization.name}", %{seats: 5})
      |> response(200)
    end

    test "validate update organization seats", %{user1: user1, organization: organization} do
      insert(:organization_user, organization: organization, user: user1, role: "write")

      result =
        build_conn()
        |> put_req_header("authorization", key_for(user1))
        |> post("api/orgs/#{organization.name}", %{seats: 0})
        |> json_response(422)

      assert result["errors"] == "number of seats cannot be less than number of members"
    end
  end

  describe "GET /api/orgs/:organization/audit_logs" do
    test "returns 404 when unauthorized", %{user1: user1, organization: organization} do
      build_conn()
      |> get("api/orgs/#{organization.name}/audit_logs")
      |> response(404)

      build_conn()
      |> put_req_header("authorization", key_for(user1))
      |> get("api/orgs/#{organization.name}/audit_logs")
      |> response(404)
    end

    test "returns the first page of audit_logs related to this organization when params page is not specified",
         %{user1: user1, organization: organization} do
      insert(:organization_user, organization: organization, user: user1, role: "read")
      insert(:audit_log, action: "organization.test", organization: organization)

      conn =
        build_conn()
        |> put_req_header("authorization", key_for(user1))
        |> get("api/orgs/#{organization.name}/audit_logs")

      assert [%{"action" => "organization.test"}] = json_response(conn, :ok)
    end
  end
end
