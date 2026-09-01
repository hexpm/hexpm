defmodule Hexpm.Accounts.SCIMTest do
  use Hexpm.DataCase

  import Mox

  alias Hexpm.Accounts.{
    AuditLogs,
    Organization,
    Organizations,
    OrganizationInvitation,
    OrganizationInvitations,
    SCIM,
    Seats
  }

  alias Hexpm.Accounts.SCIM.Resource
  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.OrgSession

  setup :verify_on_exit!

  setup do
    organization = insert(:organization, billing_seats: 4)
    admin = insert(:user)
    insert(:organization_user, organization: organization, user: admin, role: "admin")

    connection =
      insert(:organization_sso_connection,
        organization: organization,
        scim_seat_policy: "block",
        scim_role: "read",
        scim_token_first: "token-first",
        scim_token_second: "token-second"
      )

    connection = %{connection | organization: organization}

    config = Application.fetch_env!(:hexpm, :organization_sso)

    app_env(
      :hexpm,
      :organization_sso,
      Keyword.merge(config, mode: :beta, beta_organizations: [organization.name])
    )

    %{organization: organization, admin: admin, connection: connection}
  end

  describe "create_user/2" do
    test "a verified email joins the account with the provisioned role and one seat", context do
      user = insert(:user)
      email = hd(user.emails).email

      assert {:ok, %{state: :member, user: matched}} =
               SCIM.create_user(context.connection, %{"userName" => email})

      assert matched.id == user.id
      assert Organizations.get_role(context.organization, user) == "read"
      assert Seats.used(context.organization) == 2

      actions = context.organization |> AuditLogs.all_by() |> Enum.map(& &1.action)
      assert "organization.member.add" in actions
    end

    test "an unknown address becomes a pending invitation, not an account", context do
      assert {:ok, %{state: :invited, resource: resource}} =
               SCIM.create_user(context.connection, %{"userName" => "new@example.com"})

      invitation = Repo.get!(OrganizationInvitation, resource.invitation_id)
      assert invitation.email == "new@example.com"
      assert invitation.role == "read"
      # The seat is spent at acceptance, not at assignment.
      assert Seats.used(context.organization) == 1
    end

    test "a live pending invitation from an administrator is adopted, not refused", context do
      {:ok, invitation} =
        OrganizationInvitations.invite(
          context.organization,
          %{"email" => "pending@example.com", "role" => "write"},
          context.admin,
          audit: audit_data(context.admin)
        )

      assert {:ok, %{state: :invited, resource: resource}} =
               SCIM.create_user(context.connection, %{"userName" => "pending@example.com"})

      assert resource.invitation_id == invitation.id
    end

    test "a duplicate userName is a uniqueness conflict", context do
      assert {:ok, _resolved} =
               SCIM.create_user(context.connection, %{"userName" => "dup@example.com"})

      assert {:error, :uniqueness} =
               SCIM.create_user(context.connection, %{"userName" => "dup@example.com"})
    end

    test "a second resource for the same account is a uniqueness conflict", context do
      user = insert(:user)
      [primary_email] = user.emails

      other_email =
        insert(:email,
          user: user,
          primary: false,
          public: false,
          gravatar: false,
          email: "second@example.com"
        )

      assert {:ok, %{state: :member}} =
               SCIM.create_user(context.connection, %{"userName" => primary_email.email})

      assert {:error, :uniqueness} =
               SCIM.create_user(context.connection, %{"userName" => other_email.email})
    end

    test "an inactive create stores the handle and touches nothing", context do
      user = insert(:user)
      email = hd(user.emails).email

      assert {:ok, %{state: :inactive}} =
               SCIM.create_user(context.connection, %{"userName" => email, "active" => false})

      refute Organizations.get_role(context.organization, user)
      assert Seats.used(context.organization) == 1
    end

    test "a userName that is not an email is refused", context do
      assert {:error, :invalid_value} =
               SCIM.create_user(context.connection, %{"userName" => "not-an-email"})

      assert {:error, :invalid_value} = SCIM.create_user(context.connection, %{})
    end

    test "seat exhaustion under block refuses the create", context do
      organization = seats_full(context.organization)
      connection = %{context.connection | organization: organization}
      user = insert(:user)

      assert {:error, :seats_exhausted} =
               SCIM.create_user(connection, %{"userName" => hd(user.emails).email})

      refute Organizations.get_role(organization, user)
    end

    test "seat exhaustion under expand buys a seat and retries once", context do
      organization = seats_full(context.organization)

      connection = %{
        context.connection
        | organization: organization,
          scim_seat_policy: "expand"
      }

      user = insert(:user)

      # Two members with two paid seats; the expansion subscribes to exactly
      # one more than is used.
      expect(Hexpm.Billing.Mock, :update, fn name, params ->
        assert name == organization.name
        assert params["quantity"] == 3
        {:ok, %{"quantity" => 3}}
      end)

      assert {:ok, %{state: :member}} =
               SCIM.create_user(connection, %{"userName" => hd(user.emails).email})

      assert Organizations.get_role(organization, user) == "read"
    end
  end

  describe "deactivation and reactivation" do
    test "deactivating a member removes the membership and everything hanging off it",
         context do
      user = insert(:user)
      email = hd(user.emails).email

      {:ok, %{resource: resource}} =
        SCIM.create_user(context.connection, %{"userName" => email})

      connection_row = Repo.get!(Hexpm.Accounts.SSO.Connection, context.connection.id)

      identity =
        insert(:organization_sso_identity,
          organization: context.organization,
          connection: connection_row,
          user: user
        )

      {:ok, session, _token} =
        Hexpm.UserSessions.create_browser_session(user, audit: audit_data(user))

      SSO.establish_org_session!(identity, session.id)

      assert {:ok, %{state: :inactive}} =
               SCIM.patch_user(context.connection, resource.scim_id, [
                 %{"op" => "replace", "path" => "active", "value" => false}
               ])

      refute Organizations.get_role(context.organization, user)
      refute SSO.current_org_session(session.id, context.organization.id)
      assert Repo.all(OrgSession) == []
      assert Seats.used(context.organization) == 1
      # The billed quantity is untouched; only an admin changes it.
      assert Repo.get!(Organization, context.organization.id).billing_seats == 4
    end

    test "deactivating an invited person revokes the invitation", context do
      {:ok, %{resource: resource}} =
        SCIM.create_user(context.connection, %{"userName" => "invited@example.com"})

      assert {:ok, %{state: :inactive}} =
               SCIM.patch_user(context.connection, resource.scim_id, [
                 %{"op" => "replace", "path" => "active", "value" => "False"}
               ])

      assert OrganizationInvitations.all_pending(context.organization) == []
    end

    test "deactivating the last member is refused", context do
      resolved = materialized_admin(context)

      assert {:error, :last_member} =
               SCIM.patch_user(context.connection, resolved.resource.scim_id, [
                 %{"op" => "replace", "value" => %{"active" => "False"}}
               ])

      assert Organizations.get_role(context.organization, context.admin) == "admin"
    end

    test "deactivating twice is idempotent", context do
      user = insert(:user)

      {:ok, %{resource: resource}} =
        SCIM.create_user(context.connection, %{"userName" => hd(user.emails).email})

      assert {:ok, %{state: :inactive}} = deactivate(context.connection, resource)
      assert {:ok, %{state: :inactive}} = deactivate(context.connection, resource)
    end

    test "reactivating claims a seat again with the provisioned role", context do
      user = insert(:user)

      {:ok, %{resource: resource}} =
        SCIM.create_user(context.connection, %{"userName" => hd(user.emails).email})

      {:ok, _resolved} = deactivate(context.connection, resource)
      refute Organizations.get_role(context.organization, user)

      assert {:ok, %{state: :member}} =
               SCIM.patch_user(context.connection, resource.scim_id, [
                 %{"op" => "replace", "path" => "active", "value" => true}
               ])

      assert Organizations.get_role(context.organization, user) == "read"
      assert Seats.used(context.organization) == 2
    end

    test "a member removed by hand reads as inactive on the next request", context do
      user = insert(:user)

      {:ok, %{resource: resource}} =
        SCIM.create_user(context.connection, %{"userName" => hd(user.emails).email})

      :ok =
        Organizations.remove_member(context.organization, user, audit: audit_data(context.admin))

      assert {:ok, %{state: :inactive}} =
               SCIM.get_user(context.connection, resource.scim_id)
    end

    test "an accepted invitation repairs the handle to the member", context do
      {:ok, %{resource: resource}} =
        SCIM.create_user(context.connection, %{"userName" => "joiner@example.com"})

      invitation =
        Repo.get!(OrganizationInvitation, resource.invitation_id)
        |> Repo.preload(:organization)

      joiner = insert(:user)

      {:ok, _organization_user} =
        OrganizationInvitations.accept(invitation, joiner, audit: audit_data(joiner))

      assert {:ok, %{state: :member, user: user}} =
               SCIM.get_user(context.connection, resource.scim_id)

      assert user.id == joiner.id
    end
  end

  describe "replace and delete" do
    test "a PUT with active false deactivates, the Okta way", context do
      user = insert(:user)
      email = hd(user.emails).email

      {:ok, %{resource: resource}} =
        SCIM.create_user(context.connection, %{"userName" => email})

      assert {:ok, %{state: :inactive}} =
               SCIM.replace_user(context.connection, resource.scim_id, %{
                 "userName" => email,
                 "active" => false
               })

      refute Organizations.get_role(context.organization, user)
    end

    test "renaming a member relabels without rebinding the account", context do
      user = insert(:user)

      {:ok, %{resource: resource}} =
        SCIM.create_user(context.connection, %{"userName" => hd(user.emails).email})

      assert {:ok, %{state: :member, resource: resource, user: same}} =
               SCIM.replace_user(context.connection, resource.scim_id, %{
                 "userName" => "newlabel@example.com",
                 "active" => true
               })

      assert resource.user_name == "newlabel@example.com"
      assert same.id == user.id
    end

    test "renaming an invited person reinvites the new address", context do
      {:ok, %{resource: resource}} =
        SCIM.create_user(context.connection, %{"userName" => "old@example.com"})

      assert {:ok, %{state: :invited, resource: resource}} =
               SCIM.replace_user(context.connection, resource.scim_id, %{
                 "userName" => "new@example.com",
                 "active" => true
               })

      assert resource.user_name == "new@example.com"

      emails = OrganizationInvitations.all_pending(context.organization) |> Enum.map(& &1.email)
      assert "new@example.com" in emails
      refute "old@example.com" in emails
    end

    test "delete deactivates and frees the userName slot", context do
      user = insert(:user)
      email = hd(user.emails).email

      {:ok, %{resource: resource}} =
        SCIM.create_user(context.connection, %{"userName" => email})

      assert :ok = SCIM.delete_user(context.connection, resource.scim_id)
      refute Organizations.get_role(context.organization, user)
      assert {:error, :not_found} = SCIM.get_user(context.connection, resource.scim_id)

      assert {:ok, _resolved} = SCIM.create_user(context.connection, %{"userName" => email})
    end

    test "deleting the last member is refused and keeps the handle", context do
      resolved = materialized_admin(context)

      assert {:error, :last_member} =
               SCIM.delete_user(context.connection, resolved.resource.scim_id)

      assert {:ok, _resolved} =
               SCIM.get_user(context.connection, resolved.resource.scim_id)
    end
  end

  describe "listing and filtering" do
    test "the listing materializes current members and paginates stably", context do
      users = for _index <- 1..3, do: insert(:user)

      for user <- users do
        insert(:organization_user, organization: context.organization, user: user)
      end

      listing = SCIM.list_users(context.connection, 1, 2)
      assert listing.total == 4
      assert length(listing.resources) == 2

      rest = SCIM.list_users(context.connection, 3, 2)
      assert length(rest.resources) == 2

      ids = Enum.map(listing.resources ++ rest.resources, & &1.resource.scim_id)
      assert length(Enum.uniq(ids)) == 4
      assert Enum.all?(listing.resources ++ rest.resources, &(&1.state == :member))
    end

    test "the listing prefers the identity's provider email as the userName", context do
      user = insert(:user)
      insert(:organization_user, organization: context.organization, user: user)

      connection = Repo.get!(Hexpm.Accounts.SSO.Connection, context.connection.id)

      insert(:organization_sso_identity,
        organization: context.organization,
        connection: connection,
        user: user,
        provider_email: "work@corp.example.com"
      )

      listing = SCIM.list_users(context.connection, 1, 100)
      user_names = Enum.map(listing.resources, & &1.resource.user_name)
      assert "work@corp.example.com" in user_names
    end

    test "filtering by userName materializes a current member exactly once", context do
      user = insert(:user)
      insert(:organization_user, organization: context.organization, user: user)
      email = hd(user.emails).email

      assert %{state: :member} = SCIM.find_by_user_name(context.connection, email)
      assert %{state: :member} = SCIM.find_by_user_name(context.connection, email)

      assert Repo.aggregate(Resource, :count) == 1
    end

    test "filtering by userName finds nothing for outsiders", context do
      outsider = insert(:user)

      assert SCIM.find_by_user_name(context.connection, hd(outsider.emails).email) == nil
      assert Repo.aggregate(Resource, :count) == 0
    end

    test "filtering by externalId matches stored handles", context do
      {:ok, %{resource: resource}} =
        SCIM.create_user(context.connection, %{
          "userName" => "ext@example.com",
          "externalId" => "okta-123"
        })

      assert %{resource: found} = SCIM.find_by_external_id(context.connection, "okta-123")
      assert found.id == resource.id
      assert SCIM.find_by_external_id(context.connection, "unknown") == nil
    end
  end

  describe "review regressions" do
    test "deactivating a member also retires a pending invitation for the handle", context do
      {:ok, %{state: :invited, resource: resource}} =
        SCIM.create_user(context.connection, %{"userName" => "late@example.com"})

      user = insert(:user, emails: [build(:email, email: "late@example.com")])
      insert(:organization_user, organization: context.organization, user: user)

      assert {:ok, %{state: :member}} = SCIM.get_user(context.connection, resource.scim_id)

      assert {:ok, %{state: :inactive}} = deactivate(context.connection, resource)

      refute Organizations.get_role(context.organization, user)
      assert OrganizationInvitations.all_pending(context.organization) == []
    end

    test "deactivating after the invitation was accepted removes the member", context do
      {:ok, %{resource: resource}} =
        SCIM.create_user(context.connection, %{"userName" => "accepted@example.com"})

      invitation =
        Repo.get!(OrganizationInvitation, resource.invitation_id)
        |> Repo.preload(:organization)

      acceptor = insert(:user)

      {:ok, _organization_user} =
        OrganizationInvitations.accept(invitation, acceptor, audit: audit_data(acceptor))

      assert {:ok, %{state: :inactive}} = deactivate(context.connection, resource)
      refute Organizations.get_role(context.organization, acceptor)
    end

    test "the full import skips unverified primary addresses instead of binding them",
         context do
      wrong =
        insert(:user,
          emails: [build(:email, email: "collision@example.com", verified: false)]
        )

      owner = insert(:user, emails: [build(:email, email: "collision@example.com")])
      insert(:organization_user, organization: context.organization, user: wrong)
      insert(:organization_user, organization: context.organization, user: owner)

      listing = SCIM.list_users(context.connection, 1, 100)

      collision =
        Enum.find(listing.resources, &(&1.resource.user_name == "collision@example.com"))

      assert collision.resource.user_id == owner.id
      refute Enum.any?(listing.resources, &(&1.resource.user_id == wrong.id))
    end

    test "patch operations run in array order", context do
      user_a = insert(:user)
      email_a = hd(user_a.emails).email
      user_b = insert(:user)
      email_b = hd(user_b.emails).email

      {:ok, %{resource: resource}} =
        SCIM.create_user(context.connection, %{"userName" => email_a})

      {:ok, _resolved} = deactivate(context.connection, resource)

      assert {:ok, %{state: :member, resource: resource, user: activated}} =
               SCIM.patch_user(context.connection, resource.scim_id, [
                 %{"op" => "replace", "path" => "active", "value" => true},
                 %{"op" => "replace", "path" => "userName", "value" => email_b}
               ])

      assert activated.id == user_a.id
      assert resource.user_name == email_b
      assert Organizations.get_role(context.organization, user_a) == "read"
      refute Organizations.get_role(context.organization, user_b)
    end

    test "renaming to a taken name leaves the original invitation standing", context do
      {:ok, %{resource: resource}} =
        SCIM.create_user(context.connection, %{"userName" => "old@example.com"})

      {:ok, _other} = SCIM.create_user(context.connection, %{"userName" => "taken@example.com"})

      assert {:error, :uniqueness} =
               SCIM.patch_user(context.connection, resource.scim_id, [
                 %{"op" => "replace", "path" => "userName", "value" => "taken@example.com"}
               ])

      assert {:ok, %{state: :invited, resource: resource}} =
               SCIM.get_user(context.connection, resource.scim_id)

      assert resource.user_name == "old@example.com"

      emails =
        OrganizationInvitations.all_pending(context.organization) |> Enum.map(& &1.email)

      assert "old@example.com" in emails
    end
  end

  defp deactivate(connection, resource) do
    SCIM.patch_user(connection, resource.scim_id, [
      %{"op" => "replace", "path" => "active", "value" => false}
    ])
  end

  defp materialized_admin(context) do
    SCIM.find_by_user_name(context.connection, hd(context.admin.emails).email)
  end

  defp seats_full(organization) do
    filler = insert(:user)
    insert(:organization_user, organization: organization, user: filler)

    organization
    |> Ecto.Changeset.change(billing_seats: 2)
    |> Repo.update!()
  end
end
