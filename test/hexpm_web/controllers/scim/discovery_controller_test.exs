defmodule HexpmWeb.SCIM.DiscoveryControllerTest do
  use HexpmWeb.ConnCase, async: false

  alias Hexpm.Accounts.SSO

  setup do
    organization = insert(:organization)
    admin = insert(:user)
    insert(:organization_user, organization: organization, user: admin, role: "admin")
    insert(:organization_sso_connection, organization: organization)
    enable_beta_for(organization)

    {:ok, connection} =
      SSO.generate_scim_token(
        organization,
        %{"scim_seat_policy" => "block", "scim_role" => "read"},
        audit: audit_data(admin)
      )

    %{organization: organization, token: connection.scim_token}
  end

  test "serves the conformance documents to the bearer of the token", context do
    body = scim_json_response(scim_get(context.token, "/scim/v2/ServiceProviderConfig"), 200)

    assert body["patch"]["supported"] == true
    assert body["filter"]["supported"] == true
    assert body["bulk"]["supported"] == false

    body = scim_json_response(scim_get(context.token, "/scim/v2/ResourceTypes"), 200)
    assert [%{"endpoint" => "/Users"}] = body["Resources"]

    body = scim_json_response(scim_get(context.token, "/scim/v2/Schemas"), 200)
    assert [%{"id" => "urn:ietf:params:scim:schemas:core:2.0:User"}] = body["Resources"]
  end

  test "an unknown path is a SCIM error", context do
    body = scim_json_response(scim_get(context.token, "/scim/v2/Groups"), 404)

    assert body["schemas"] == ["urn:ietf:params:scim:api:messages:2.0:Error"]
    assert body["status"] == "404"
  end

  test "a missing or wrong token is refused with the SCIM error schema" do
    conn = build_conn() |> get("/scim/v2/ServiceProviderConfig")
    body = scim_json_response(conn, 401)

    assert body["schemas"] == ["urn:ietf:params:scim:api:messages:2.0:Error"]
    assert get_resp_header(conn, "www-authenticate") == [~s(Bearer realm="hexpm-scim")]

    assert scim_json_response(scim_get("wrong-token", "/scim/v2/ServiceProviderConfig"), 401)
  end

  test "the token stops working when the organization leaves the beta", context do
    config = Application.fetch_env!(:hexpm, :organization_sso)

    app_env(
      :hexpm,
      :organization_sso,
      Keyword.merge(config, beta_organizations: ["someone-else"])
    )

    assert scim_json_response(scim_get(context.token, "/scim/v2/ServiceProviderConfig"), 401)
  end

  test "requests are rate limited per address", context do
    conn =
      %{build_conn() | remote_ip: {203, 0, 113, 9}}
      |> put_req_header("authorization", "Bearer #{context.token}")
      |> get("/scim/v2/ServiceProviderConfig")

    assert response(conn, 200)
    assert [_limit] = get_resp_header(conn, "x-ratelimit-limit")
  end

  test "the surface does not exist while SSO is off", context do
    config = Application.fetch_env!(:hexpm, :organization_sso)
    app_env(:hexpm, :organization_sso, Keyword.put(config, :mode, :off))

    assert scim_json_response(scim_get(context.token, "/scim/v2/ServiceProviderConfig"), 404)
  end

  defp scim_get(token, path) do
    build_conn()
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("accept", "application/scim+json")
    |> get(path)
  end

  defp scim_json_response(conn, status) do
    assert response_content_type(conn, :scim) =~ "application/scim+json"

    conn
    |> response(status)
    |> JSON.decode!()
  end

  defp enable_beta_for(organization) do
    config = Application.fetch_env!(:hexpm, :organization_sso)

    app_env(
      :hexpm,
      :organization_sso,
      Keyword.merge(config, mode: :beta, beta_organizations: [organization.name])
    )
  end
end
