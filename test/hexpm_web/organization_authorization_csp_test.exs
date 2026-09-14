defmodule HexpmWeb.OrganizationAuthorizationCSPTest do
  use HexpmWeb.ConnCase

  alias Hexpm.Accounts.{SSO, TFA}

  @redirect_uri "https://acme.hexorgs.pm/oauth/callback"
  @origin "https://acme.hexorgs.pm"

  setup do
    PlugAttack.Storage.Ets.clean(HexpmWeb.Plugs.Attack.Storage)
    app_env(:hexpm, :organization_tfa, mode: :enabled, beta_organizations: [])
    stub(Hexpm.Billing.Mock, :get, fn _, _ -> nil end)
    user = insert(:user_with_tfa)
    organization = insert(:organization, tfa_required_at: DateTime.add(DateTime.utc_now(), -1))
    membership = insert(:organization_user, organization: organization, user: user, role: "admin")
    client = insert(:oauth_client, redirect_uris: ["https://*.hexorgs.pm/oauth/callback"])

    %{user: user, organization: organization, membership: membership, client: client}
  end

  test "login TOTP completes an external callback", c do
    mock_pwned()
    {authorization, target} = authorization(c)
    path = authorization_path(authorization)

    conn = build_conn() |> get(path)
    assert redirected_to(conn) =~ "/login?return="
    conn = conn |> recycle() |> get(redirected_to(conn))
    assert html_response(conn, 200) =~ "Log in"

    conn =
      conn
      |> recycle()
      |> post("/login", %{username: c.user.username, password: "password", return: path})

    assert redirected_to(conn) == "/tfa"
    conn = conn |> recycle() |> get("/tfa")
    assert html_response(conn, 200) =~ "Two-factor authentication"
    assert form_actions(conn) == ["'self'", @origin]

    conn =
      conn
      |> recycle()
      |> post("/tfa", %{code: TFA.time_based_token(c.user.tfa.secret)})

    assert redirected_to(conn) == path
    conn = conn |> recycle() |> get(path)
    assert redirected_to(conn) =~ @redirect_uri <> "?"
    assert Repo.get!(Hexpm.UserSession, target.id).expires_at == target.expires_at
    refute SSO.get_authorization(authorization.raw_code, c.user)
  end

  test "shared authorization and enrollment forms allow only the registered callback origin", c do
    user = insert(:user)
    insert(:organization_user, organization: c.organization, user: user, role: "read")
    {authorization, target} = authorization(%{c | user: user})
    path = authorization_path(authorization)

    conn =
      build_conn()
      |> test_login(user)
      |> get(path <> "&redirect_uri=https%3A%2F%2Fevil.example")

    assert html_response(conn, 200) =~ "2FA enrollment required"
    assert form_actions(conn) == ["'self'", @origin]

    conn =
      conn
      |> recycle()
      |> post("/organizations/authorize", %{
        code: authorization.raw_code,
        organization: c.organization.name
      })

    assert redirected_to(conn) == "/dashboard/security"
    conn = conn |> recycle() |> get("/dashboard/security")
    assert html_response(conn, 200)
    assert form_actions(conn) == ["'self'", @origin]

    conn = conn |> recycle() |> post("/dashboard/security/enable-tfa")
    conn = conn |> recycle() |> get(redirected_to(conn))
    assert html_response(conn, 200) =~ "verification_code"
    assert form_actions(conn) == ["'self'", @origin]
    secret = get_session(conn, :tfa_setup_secret)

    conn =
      conn
      |> recycle()
      |> post("/dashboard/security/verify-tfa-code", %{
        "verification_code" => TFA.time_based_token(secret)
      })

    assert redirected_to(conn) == path
    conn = conn |> recycle() |> get(path)
    assert redirected_to(conn) =~ @redirect_uri
    assert Repo.get!(Hexpm.UserSession, target.id).expires_at == target.expires_at
  end

  test "cancellation forms permit the registered callback", c do
    user = insert(:user)
    insert(:organization_user, organization: c.organization, user: user, role: "read")
    {authorization, _target} = authorization(%{c | user: user})
    conn = build_conn() |> test_login(user) |> get(authorization_path(authorization))
    assert html_response(conn, 200) =~ "Cancel"
    assert form_actions(conn) == ["'self'", @origin]

    conn =
      conn
      |> recycle()
      |> post("/organizations/authorize", %{code: authorization.raw_code, action: "cancel"})

    assert redirected_to(conn) =~ @redirect_uri
    assert redirected_to(conn) =~ "organization_authorization=cancelled"
    refute SSO.get_authorization(authorization.raw_code, user)
  end

  test "sudo TOTP and recovery forms allow the pending registered callback", c do
    {authorization, _target} = authorization(c)

    conn =
      build_conn()
      |> test_login(c.user, sudo: false)
      |> get(authorization_path(authorization))

    assert redirected_to(conn) == "/sudo"
    conn = conn |> recycle() |> get("/sudo")
    assert html_response(conn, 200) =~ "Verify your identity"
    assert form_actions(conn) == ["'self'", @origin]
    conn = conn |> recycle() |> get("/sudo/recovery")
    assert html_response(conn, 200) =~ "Enter recovery code"
    assert form_actions(conn) == ["'self'", @origin]
  end

  for failure <- [
        :unknown,
        :expired,
        :consumed,
        :revoked,
        :target_expired,
        :mismatch,
        :unregistered,
        :removed
      ] do
    @tag failure: failure
    test "#{failure} authorization never adds a callback origin to forms",
         %{failure: failure} = c do
      {authorization, target} = authorization(c)

      invalidate(c, authorization, target, failure)

      user = if failure == :mismatch, do: insert(:user_with_tfa), else: c.user
      code = if failure == :unknown, do: "unknown", else: authorization.raw_code
      path = "/organizations/authorize?" <> URI.encode_query(%{code: code})

      conn = build_conn() |> test_login(user) |> get(path)
      assert form_actions(conn) == ["'self'"]

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "tfa_user_id" => %{
            "uid" => user.id,
            "at" => NaiveDateTime.to_iso8601(NaiveDateTime.utc_now()),
            "return" => path
          }
        })
        |> get("/tfa")

      assert conn.assigns.current_user == nil
      assert html_response(conn, 200)
      assert form_actions(conn) == ["'self'"]

      for {page, key} <- [
            {"/dashboard/security", :tfa_return_to},
            {"/sudo", "sudo_return_to"},
            {"/sudo/recovery", "sudo_return_to"}
          ] do
        conn =
          build_conn()
          |> test_login(user, sudo: page == "/dashboard/security")
          |> put_session(key, path)
          |> get(page)

        assert html_response(conn, 200)
        assert form_actions(conn) == ["'self'"]
      end
    end
  end

  test "unrelated or external return paths do not authorize a callback origin", c do
    {authorization, _target} = authorization(c)

    for path <- [
          "https://evil.example" <> authorization_path(authorization),
          "//evil.example" <> authorization_path(authorization),
          "/dashboard/security?" <> URI.encode_query(%{code: authorization.raw_code}),
          "/organizations/authorize?code=unknown&redirect_uri=https://evil.example",
          "/organizations/authorize"
        ] do
      conn =
        build_conn()
        |> test_login(c.user)
        |> put_session(:tfa_return_to, path)
        |> get("/dashboard/security")

      assert html_response(conn, 200)
      assert form_actions(conn) == ["'self'"]
    end
  end

  defp invalidate(c, authorization, target, failure) do
    case failure do
      :expired ->
        authorization
        |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1))
        |> Repo.update!()

      :consumed ->
        :ok = SSO.consume_authorization!(authorization)

      :revoked ->
        target |> Ecto.Changeset.change(revoked_at: DateTime.utc_now()) |> Repo.update!()

      :target_expired ->
        target
        |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1))
        |> Repo.update!()

      :unregistered ->
        c.client
        |> Ecto.Changeset.change(redirect_uris: ["https://other.example/oauth/callback"])
        |> Repo.update!()

      :removed ->
        Repo.delete!(c.membership)

      _ ->
        :ok
    end
  end

  defp authorization(c) do
    target = insert(:oauth_session, user: c.user, client_id: c.client.client_id)

    {:ok, authorization} =
      SSO.request_authorization(c.user, target.id, [c.organization.name],
        redirect_uri: @redirect_uri,
        state: "docs-state"
      )

    {authorization, target}
  end

  defp authorization_path(authorization) do
    "/organizations/authorize?" <> URI.encode_query(%{code: authorization.raw_code})
  end

  defp form_actions(conn) do
    [csp] = get_resp_header(conn, "content-security-policy")
    [actions] = Regex.run(~r/(?:^|;)\s*form-action ([^;]+)/, csp, capture: :all_but_first)
    String.split(actions)
  end
end
