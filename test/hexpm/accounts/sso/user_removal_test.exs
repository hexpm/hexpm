defmodule Hexpm.Accounts.SSO.UserRemovalTest do
  use Hexpm.DataCase, async: true

  alias Ecto.Multi
  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.{Identity, OrgSession}

  test "user deletion locks memberships before deleting SSO transactions" do
    organization = insert(:organization)
    user = insert(:user)
    insert(:organization_user, organization: organization, user: user)
    connection = insert(:organization_sso_connection, organization: organization)
    transaction = insert_transaction(connection, user)

    multi =
      Multi.new()
      |> SSO.lock_user_removal(user)
      |> SSO.delete_user_transactions(user)

    assert multi |> Multi.to_list() |> Enum.map(&elem(&1, 0)) == [
             :organization_sso_user_removal_locks,
             :organization_sso_user_transactions
           ]

    assert {:ok, changes} = Repo.transaction(multi)
    assert changes.organization_sso_user_removal_locks == :locked
    refute Repo.get(SSO.Transaction, transaction.id)
  end

  defp insert_transaction(connection, user) do
    Repo.insert!(%SSO.Transaction{
      user_id: user.id,
      connection_id: connection.id,
      state_hash: :crypto.hash(:sha256, "state-#{System.unique_integer([:positive])}"),
      kind: "login",
      secret_slot: "active",
      connection_version: connection.version,
      secret_version: connection.version,
      redirect_uri: "https://hex.pm/sso/callback",
      expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
    })
  end

  test "member removal deletes organization access sessions before their identities" do
    organization = insert(:organization)
    user = insert(:user)

    operations =
      Multi.new()
      |> SSO.delete_member_identities(organization, user)
      |> Multi.to_list()
      |> Enum.map(&elem(&1, 0))

    assert operations == [
             :organization_sso_sessions,
             :organization_sso_identities
           ]
  end

  test "member removal deletes the organization access sessions it granted" do
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

    {:ok, user_session, _token} =
      Hexpm.UserSessions.create_browser_session(user, audit: audit_data(user))

    SSO.establish_org_session!(identity, user_session.id)
    assert SSO.current_org_session(user_session.id, organization.id)

    {:ok, _changes} =
      Multi.new()
      |> SSO.delete_member_identities(organization, user)
      |> Repo.transaction()

    refute Repo.exists?(OrgSession)
    refute Repo.exists?(Identity)
    refute SSO.current_org_session(user_session.id, organization.id)
  end

  test "deleting a user takes their organization access sessions with it" do
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

    {:ok, user_session, _token} =
      Hexpm.UserSessions.create_browser_session(user, audit: audit_data(user))

    SSO.establish_org_session!(identity, user_session.id)

    Repo.delete!(user)

    refute Repo.exists?(OrgSession)
  end
end
