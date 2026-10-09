defmodule HexpmWeb.Dashboard.BillingProxyControllerAuthTest do
  # Sync: the token path is application environment every billing call reads.
  use HexpmWeb.ConnCase, async: false

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "token")
    File.write!(path, "service-account-token")

    Application.put_env(:hexpm, :billing_token_path, path)
    on_exit(fn -> Application.delete_env(:hexpm, :billing_token_path) end)

    organization = insert(:organization)
    admin = insert(:user)
    insert(:organization_user, organization: organization, user: admin, role: "admin")

    %{admin: admin, organization: organization}
  end

  test "forwards with the service account token", context do
    expect(Hexpm.HTTP.Mock, :post, fn _url, headers, _body, _opts ->
      assert List.keyfind(headers, "authorization", 0) ==
               {"authorization", "Bearer service-account-token"}

      {:ok, 200, [], %{"client_secret" => "seti_123"}}
    end)

    conn =
      build_conn()
      |> test_login(context.admin)
      |> post("/dashboard/billing-api/api/customers/#{context.organization.name}/setup_intent")

    assert json_response(conn, 200)["client_secret"] == "seti_123"
  end
end
