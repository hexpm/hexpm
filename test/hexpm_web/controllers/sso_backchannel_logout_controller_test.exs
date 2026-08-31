defmodule HexpmWeb.SSOBackchannelLogoutControllerTest do
  use HexpmWeb.ConnCase, async: false

  import Mox

  alias Hexpm.Accounts.AuditLog
  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.{Connection, Error, OrgSession}

  setup :verify_on_exit!

  setup do
    organization = insert(:organization)
    user = insert(:user)
    insert(:organization_user, organization: organization, user: user)
    connection = insert(:organization_sso_connection, organization: organization)

    identity =
      insert(:organization_sso_identity,
        organization: organization,
        connection: connection,
        user: user
      )

    enable_beta_for(organization)

    %{organization: organization, user: user, connection: connection, identity: identity}
  end

  test "a sid-scoped token ends the sessions from that provider session and no other",
       context do
    {_session, revoked} = establish_session(context, "sid-1")
    {survivor_session, _survivor} = establish_session(context, "sid-2")
    copy = grant_copy(context, revoked)

    expect_logout_token(context.connection, ok_claims(sid: "sid-1"))

    conn = post_logout(context.organization)

    assert response(conn, 200) == ""
    assert get_resp_header(conn, "cache-control") == ["no-store"]

    assert Repo.get!(OrgSession, revoked.id).revoked_at
    assert Repo.get!(OrgSession, copy.id).revoked_at
    assert SSO.current_org_session(survivor_session.id, context.organization.id)

    assert [audit] = audit_entries("sso.backchannel_logout")
    assert audit.params["organization"]["id"] == context.organization.id
    assert audit.params["user_id"] == context.user.id
    assert audit.params["sid_scoped"] == true
    assert audit.params["revoked_count"] == 2
  end

  test "a token with no sid ends everything the identity holds, sessions without a sid included",
       context do
    {no_sid_session, _no_sid} = establish_session(context, nil)
    {sid_session, _with_sid} = establish_session(context, "sid-1")

    expect_logout_token(context.connection, ok_claims(sid: nil))

    assert response(post_logout(context.organization), 200)

    refute SSO.current_org_session(no_sid_session.id, context.organization.id)
    refute SSO.current_org_session(sid_session.id, context.organization.id)
  end

  test "an unknown subject succeeds and revokes nothing", context do
    {session, _org_session} = establish_session(context, "sid-1")

    expect_logout_token(context.connection, ok_claims(subject: "00u-somebody-else"))

    assert response(post_logout(context.organization), 200)
    assert SSO.current_org_session(session.id, context.organization.id)
    assert audit_entries("sso.backchannel_logout") == []
  end

  test "a replayed token succeeds and changes nothing further", context do
    {session, org_session} = establish_session(context, "sid-1")

    expect(Hexpm.Accounts.SSO.OIDC.Mock, :validate_logout_token, 2, fn _connection, _token ->
      ok_claims(sid: "sid-1")
    end)

    assert response(post_logout(context.organization), 200)
    revoked_at = Repo.get!(OrgSession, org_session.id).revoked_at
    assert revoked_at

    assert response(post_logout(context.organization), 200)
    assert Repo.get!(OrgSession, org_session.id).revoked_at == revoked_at
    refute SSO.current_org_session(session.id, context.organization.id)
  end

  test "an invalid token is refused and recorded for the administrator", context do
    expect(Hexpm.Accounts.SSO.OIDC.Mock, :validate_logout_token, fn _connection, _token ->
      {:error, %Error{stage: :logout_token, code: :nonce_present}}
    end)

    assert response(post_logout(context.organization), 400)

    assert [failure] = SSO.failures(context.connection)
    assert failure.stage == "logout_token"
    assert failure.code == "nonce_present"
  end

  test "a refreshed signing-key document is persisted", context do
    expires_at = DateTime.add(DateTime.utc_now(), 600, :second)
    jwks = %{"keys" => [%{"kid" => "rotated"}]}

    expect_logout_token(
      context.connection,
      ok_claims(jwks_document: jwks, jwks_expires_at: expires_at)
    )

    assert response(post_logout(context.organization), 200)
    assert Repo.get!(Connection, context.connection.id).jwks_document == jwks
  end

  test "a request without a logout token is a bad request", context do
    conn =
      build_conn()
      |> post("/sso/backchannel-logout/#{context.organization.name}", %{})

    assert response(conn, 400)
  end

  test "an organization without a connection is not found", context do
    other = insert(:organization)
    enable_beta_for([context.organization, other])

    conn =
      build_conn()
      |> post("/sso/backchannel-logout/#{other.name}", %{"logout_token" => "logout-token"})

    assert response(conn, 404)
  end

  test "an unknown organization is not found" do
    conn =
      build_conn()
      |> post("/sso/backchannel-logout/nobody", %{"logout_token" => "logout-token"})

    assert response(conn, 404)
  end

  test "an organization outside the beta is not found", context do
    enable_beta_for([])

    assert response(post_logout(context.organization), 404)
  end

  test "the endpoint does not exist while SSO is off", context do
    config = Application.fetch_env!(:hexpm, :organization_sso)
    app_env(:hexpm, :organization_sso, Keyword.put(config, :mode, :off))

    assert response(post_logout(context.organization), 404)
  end

  defp post_logout(organization) do
    build_conn()
    |> post("/sso/backchannel-logout/#{organization.name}", %{"logout_token" => "logout-token"})
  end

  defp ok_claims(overrides) do
    {:ok,
     Enum.into(overrides, %{
       issuer: "https://identity.example.com/oauth2/default",
       subject: "00u123",
       sid: nil,
       jwks_document: nil,
       jwks_expires_at: nil
     })}
  end

  defp expect_logout_token(connection, result) do
    expect(Hexpm.Accounts.SSO.OIDC.Mock, :validate_logout_token, fn received, token ->
      assert received.id == connection.id
      assert token == "logout-token"
      result
    end)
  end

  defp establish_session(context, sid) do
    {:ok, session, _token} =
      Hexpm.UserSessions.create_browser_session(context.user, audit: audit_data(context.user))

    org_session = SSO.establish_org_session!(context.identity, session.id, sid)
    {session, org_session}
  end

  defp grant_copy(context, source) do
    {:ok, session, _token} =
      Hexpm.UserSessions.create_browser_session(context.user, audit: audit_data(context.user))

    [copy] = SSO.grant_org_sessions!(source.user_session_id, session.id, context.user.id)
    assert copy.sid == source.sid
    copy
  end

  defp audit_entries(action) do
    Repo.all(from(log in AuditLog, where: log.action == ^action))
  end

  defp enable_beta_for(organizations) do
    config = Application.fetch_env!(:hexpm, :organization_sso)
    organizations = List.wrap(organizations)

    app_env(
      :hexpm,
      :organization_sso,
      Keyword.merge(config,
        mode: :beta,
        beta_organizations: Enum.map(organizations, & &1.name)
      )
    )
  end
end
