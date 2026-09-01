defmodule HexpmWeb.SCIM.UserControllerTest do
  use HexpmWeb.ConnCase, async: false

  alias Hexpm.Accounts.{Organizations, SSO}

  setup do
    organization = insert(:organization, billing_seats: 4)
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

    %{organization: organization, admin: admin, token: connection.scim_token}
  end

  test "provisioning a person with a Hex account creates the membership", context do
    user = insert(:user)
    email = hd(user.emails).email

    conn =
      scim_conn(context.token)
      |> post("/scim/v2/Users", scim_body(%{"userName" => email, "externalId" => "okta-1"}))

    body = scim_json_response(conn, 201)

    assert body["userName"] == email
    assert body["active"] == true
    assert body["externalId"] == "okta-1"
    assert body["displayName"] == user.username
    assert [location] = get_resp_header(conn, "location")
    assert location =~ body["id"]
    assert Organizations.get_role(context.organization, user) == "read"
  end

  test "provisioning an unknown address answers active with a pending invitation", context do
    body =
      scim_conn(context.token)
      |> post("/scim/v2/Users", scim_body(%{"userName" => "new@example.com"}))
      |> scim_json_response(201)

    assert body["active"] == true
    refute body["displayName"]
  end

  test "a duplicate create is a 409 the provider recovers from by filtering", context do
    params = scim_body(%{"userName" => "dup@example.com"})

    assert scim_conn(context.token) |> post("/scim/v2/Users", params) |> response(201)

    body = scim_conn(context.token) |> post("/scim/v2/Users", params) |> scim_json_response(409)
    assert body["scimType"] == "uniqueness"

    listing =
      scim_conn(context.token)
      |> get("/scim/v2/Users", %{"filter" => ~s(userName eq "dup@example.com")})
      |> scim_json_response(200)

    assert [%{"userName" => "dup@example.com"}] = listing["Resources"]
  end

  test "a full sync lists every member with pagination", context do
    for _index <- 1..2 do
      user = insert(:user)
      insert(:organization_user, organization: context.organization, user: user)
    end

    page =
      scim_conn(context.token)
      |> get("/scim/v2/Users", %{"startIndex" => "1", "count" => "2"})
      |> scim_json_response(200)

    assert page["totalResults"] == 3
    assert length(page["Resources"]) == 2

    rest =
      scim_conn(context.token)
      |> get("/scim/v2/Users", %{"startIndex" => "3", "count" => "2"})
      |> scim_json_response(200)

    assert length(rest["Resources"]) == 1
  end

  test "an unsupported filter is refused", context do
    body =
      scim_conn(context.token)
      |> get("/scim/v2/Users", %{"filter" => ~s(emails co "corp")})
      |> scim_json_response(400)

    assert body["scimType"] == "invalidFilter"
  end

  test "Okta's PUT deactivate removes the membership", context do
    user = insert(:user)
    email = hd(user.emails).email

    created =
      scim_conn(context.token)
      |> post("/scim/v2/Users", scim_body(%{"userName" => email}))
      |> scim_json_response(201)

    body =
      scim_conn(context.token)
      |> put(
        "/scim/v2/Users/#{created["id"]}",
        scim_body(%{"userName" => email, "active" => false})
      )
      |> scim_json_response(200)

    assert body["active"] == false
    refute Organizations.get_role(context.organization, user)
  end

  test "Entra's PATCH with string booleans deactivates and reactivates", context do
    user = insert(:user)
    email = hd(user.emails).email

    created =
      scim_conn(context.token)
      |> post("/scim/v2/Users", scim_body(%{"userName" => email}))
      |> scim_json_response(201)

    patch_body = fn value ->
      scim_body(%{
        "schemas" => ["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
        "Operations" => [%{"op" => "Replace", "path" => "active", "value" => value}]
      })
    end

    body =
      scim_conn(context.token)
      |> patch("/scim/v2/Users/#{created["id"]}", patch_body.("False"))
      |> scim_json_response(200)

    assert body["active"] == false
    refute Organizations.get_role(context.organization, user)

    body =
      scim_conn(context.token)
      |> patch("/scim/v2/Users/#{created["id"]}", patch_body.("True"))
      |> scim_json_response(200)

    assert body["active"] == true
    assert Organizations.get_role(context.organization, user) == "read"
  end

  test "DELETE deactivates, drops the handle, and frees the name", context do
    user = insert(:user)
    email = hd(user.emails).email

    created =
      scim_conn(context.token)
      |> post("/scim/v2/Users", scim_body(%{"userName" => email}))
      |> scim_json_response(201)

    conn = scim_conn(context.token) |> delete("/scim/v2/Users/#{created["id"]}")
    assert response(conn, 204)
    refute Organizations.get_role(context.organization, user)

    assert scim_conn(context.token)
           |> get("/scim/v2/Users/#{created["id"]}")
           |> scim_json_response(404)

    assert scim_conn(context.token)
           |> post("/scim/v2/Users", scim_body(%{"userName" => email}))
           |> response(201)
  end

  test "seat exhaustion is a 409 naming the fix", context do
    Repo.update!(Ecto.Changeset.change(context.organization, billing_seats: 1))
    user = insert(:user)

    body =
      scim_conn(context.token)
      |> post("/scim/v2/Users", scim_body(%{"userName" => hd(user.emails).email}))
      |> scim_json_response(409)

    assert body["detail"] =~ "no seats left"
  end

  test "removing the last member is refused", context do
    listing =
      scim_conn(context.token)
      |> get("/scim/v2/Users")
      |> scim_json_response(200)

    assert [%{"id" => id}] = listing["Resources"]

    assert scim_conn(context.token)
           |> delete("/scim/v2/Users/#{id}")
           |> scim_json_response(409)

    assert Organizations.get_role(context.organization, context.admin) == "admin"
  end

  test "an unknown or malformed id is not found", context do
    assert scim_conn(context.token)
           |> get("/scim/v2/Users/#{Ecto.UUID.generate()}")
           |> scim_json_response(404)

    assert scim_conn(context.token)
           |> get("/scim/v2/Users/not-a-uuid")
           |> scim_json_response(404)
  end

  test "a userName that is not an email is refused", context do
    body =
      scim_conn(context.token)
      |> post("/scim/v2/Users", scim_body(%{"userName" => "just-a-name"}))
      |> scim_json_response(400)

    assert body["scimType"] == "invalidValue"
  end

  defp scim_conn(token) do
    build_conn()
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("accept", "application/scim+json")
    |> put_req_header("content-type", "application/scim+json")
  end

  defp scim_body(map) do
    JSON.encode!(map)
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
