defmodule Hexpm.Accounts.SSO.SCIMConfigTest do
  use Hexpm.DataCase

  alias Hexpm.Accounts.{AuditLogs, SSO}
  alias Hexpm.Accounts.SSO.Connection

  @params %{"scim_seat_policy" => "block", "scim_role" => "read"}

  setup do
    organization = insert(:organization)
    admin = insert(:user)
    member = insert(:user)
    insert(:organization_user, organization: organization, user: admin, role: "admin")
    insert(:organization_user, organization: organization, user: member, role: "read")
    connection = insert(:organization_sso_connection, organization: organization)
    enable_beta_for(organization)

    %{organization: organization, admin: admin, member: member, connection: connection}
  end

  test "generating a token forces the seat-policy choice", context do
    assert {:error, %Ecto.Changeset{} = changeset} =
             SSO.generate_scim_token(context.organization, %{"scim_role" => "read"},
               audit: audit_data(context.admin)
             )

    assert %{scim_seat_policy: "can't be blank"} = errors_on(changeset)
    refute Connection.scim_enabled?(Repo.get!(Connection, context.connection.id))
  end

  test "a generated token authenticates, and only the hash is stored", context do
    assert {:ok, connection} =
             SSO.generate_scim_token(context.organization, @params,
               audit: audit_data(context.admin)
             )

    assert is_binary(connection.scim_token)
    assert {:ok, authenticated} = SSO.scim_auth(connection.scim_token)
    assert authenticated.id == connection.id
    assert authenticated.organization.id == context.organization.id

    stored = Repo.get!(Connection, connection.id)
    assert Connection.scim_enabled?(stored)
    refute stored.scim_token
    refute stored.scim_token_first == connection.scim_token
    assert stored.scim_seat_policy == "block"

    actions = context.organization |> AuditLogs.all_by() |> Enum.map(& &1.action)
    assert "sso.scim.token.generate" in actions
  end

  test "regenerating invalidates the old token", context do
    {:ok, first} =
      SSO.generate_scim_token(context.organization, @params, audit: audit_data(context.admin))

    {:ok, second} =
      SSO.generate_scim_token(context.organization, @params, audit: audit_data(context.admin))

    assert :error = SSO.scim_auth(first.scim_token)
    assert {:ok, _connection} = SSO.scim_auth(second.scim_token)
  end

  test "deleting the token turns provisioning off and keeps the settings", context do
    {:ok, connection} =
      SSO.generate_scim_token(context.organization, @params, audit: audit_data(context.admin))

    assert {:ok, _connection} =
             SSO.delete_scim_token(context.organization, audit: audit_data(context.admin))

    assert :error = SSO.scim_auth(connection.scim_token)

    stored = Repo.get!(Connection, connection.id)
    refute Connection.scim_enabled?(stored)
    assert stored.scim_seat_policy == "block"

    actions = context.organization |> AuditLogs.all_by() |> Enum.map(& &1.action)
    assert "sso.scim.token.delete" in actions
  end

  test "settings can change while provisioning is on, but the policy cannot be dropped",
       context do
    {:ok, _connection} =
      SSO.generate_scim_token(context.organization, @params, audit: audit_data(context.admin))

    assert {:ok, connection} =
             SSO.configure_scim(
               context.organization,
               %{"scim_seat_policy" => "expand", "scim_role" => "write"},
               audit: audit_data(context.admin)
             )

    assert connection.scim_seat_policy == "expand"
    assert connection.scim_role == "write"

    assert {:error, %Ecto.Changeset{}} =
             SSO.configure_scim(
               context.organization,
               %{"scim_seat_policy" => "", "scim_role" => "write"},
               audit: audit_data(context.admin)
             )
  end

  test "only an administrator changes provisioning", context do
    assert {:error, :admin_required} =
             SSO.generate_scim_token(context.organization, @params,
               audit: audit_data(context.member)
             )
  end

  test "an unknown token does not authenticate", context do
    {:ok, _connection} =
      SSO.generate_scim_token(context.organization, @params, audit: audit_data(context.admin))

    assert :error = SSO.scim_auth("not-a-token")
    assert :error = SSO.scim_auth(String.duplicate("a", 32))
  end

  test "a token stops working when the organization leaves the beta", context do
    {:ok, connection} =
      SSO.generate_scim_token(context.organization, @params, audit: audit_data(context.admin))

    config = Application.fetch_env!(:hexpm, :organization_sso)
    app_env(:hexpm, :organization_sso, Keyword.merge(config, beta_organizations: []))

    assert :error = SSO.scim_auth(connection.scim_token)
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
