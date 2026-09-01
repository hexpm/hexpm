defmodule HexpmWeb.Dashboard.BillingProxyControllerTest do
  use HexpmWeb.ConnCase, async: true

  setup do
    organization = insert(:organization)
    admin = insert(:user)
    insert(:organization_user, organization: organization, user: admin, role: "admin")

    %{admin: admin, organization: organization}
  end

  test "forwards a setup intent for an administrator in sudo mode", context do
    stub(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, _opts ->
      {:ok, 200, [], %{"client_secret" => "seti_123"}}
    end)

    conn =
      build_conn()
      |> test_login(context.admin)
      |> post("/dashboard/billing-api/api/customers/#{context.organization.name}/setup_intent")

    assert json_response(conn, 200)["client_secret"] == "seti_123"
  end

  test "takes sudo before it forwards anything", context do
    stub(Hexpm.HTTP.Mock, :post, fn _url, _headers, _body, _opts ->
      flunk("the billing service was called without sudo")
    end)

    conn =
      build_conn()
      |> test_login(context.admin, sudo: false)
      |> post("/dashboard/billing-api/api/customers/#{context.organization.name}/setup_intent")

    assert redirected_to(conn) == "/sudo"
  end

  test "requires login", context do
    conn =
      post(
        build_conn(),
        "/dashboard/billing-api/api/customers/#{context.organization.name}/setup_intent"
      )

    assert redirected_to(conn) =~ "/login"
  end
end
