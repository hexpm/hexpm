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
  alias Hexpm.Emails.OutboxEntry

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
               create_user(context.connection, %{"userName" => email})

      assert matched.id == user.id
      assert Organizations.get_role(context.organization, user) == "read"
      assert Seats.used(context.organization) == 2

      actions = context.organization |> AuditLogs.all_by() |> Enum.map(& &1.action)
      assert "organization.member.add" in actions
    end

    test "an organization 2FA policy refuses the join until the person enrolls", context do
      require_tfa(context.organization)

      user = insert(:user)

      assert {:error, :tfa_enrollment_required} =
               create_user(context.connection, %{"userName" => hd(user.emails).email})

      refute Organizations.get_role(context.organization, user)
      assert Seats.used(context.organization) == 1
      assert Repo.all(Resource) == []

      enrolled = insert(:user_with_tfa)

      assert {:ok, %{state: :member}} =
               create_user(context.connection, %{"userName" => hd(enrolled.emails).email})

      assert Organizations.get_role(context.organization, enrolled) == "read"
    end

    test "a 2FA policy does not touch someone who is already a member", context do
      require_tfa(context.organization)

      member = insert(:user)

      insert(:organization_user,
        organization: context.organization,
        user: member,
        role: "write"
      )

      assert {:ok, %{state: :member}} =
               create_user(context.connection, %{"userName" => hd(member.emails).email})

      assert Organizations.get_role(context.organization, member) == "write"
    end

    test "an unknown address becomes a pending invitation, not an account", context do
      assert {:ok, %{state: :invited, resource: resource}} =
               create_user(context.connection, %{"userName" => "new@example.com"})

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
               create_user(context.connection, %{"userName" => "pending@example.com"})

      assert resource.invitation_id == invitation.id
    end

    test "a duplicate userName is a uniqueness conflict", context do
      assert {:ok, _resolved} =
               create_user(context.connection, %{"userName" => "dup@example.com"})

      assert {:error, :uniqueness} =
               create_user(context.connection, %{"userName" => "dup@example.com"})
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
               create_user(context.connection, %{"userName" => primary_email.email})

      assert {:error, :uniqueness} =
               create_user(context.connection, %{"userName" => other_email.email})
    end

    test "an inactive create stores the handle and touches nothing", context do
      user = insert(:user)
      email = hd(user.emails).email

      assert {:ok, %{state: :inactive}} =
               create_user(context.connection, %{"userName" => email, "active" => false})

      refute Organizations.get_role(context.organization, user)
      assert Seats.used(context.organization) == 1
    end

    test "a userName that is not an email is refused", context do
      assert {:error, :invalid_value} =
               create_user(context.connection, %{"userName" => "not-an-email"})

      assert {:error, :invalid_value} = create_user(context.connection, %{})
    end

    test "seat exhaustion under block refuses the create and tells the administrators",
         context do
      organization = seats_full(context.organization)
      connection = %{context.connection | organization: organization}
      user = insert(:user)

      assert {:error, :seats_exhausted} =
               create_user(connection, %{"userName" => hd(user.emails).email})

      refute Organizations.get_role(organization, user)

      assert Repo.get_by(OutboxEntry,
               group_key: "sso.seats_exhausted:seats_exhausted:#{connection.id}"
             )
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
               create_user(connection, %{"userName" => hd(user.emails).email})

      assert Organizations.get_role(organization, user) == "read"
    end
  end

  describe "deactivation and reactivation" do
    test "deactivating a member removes the membership and everything hanging off it",
         context do
      user = insert(:user)
      email = hd(user.emails).email

      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => email})

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
               patch_user(context.connection, resource.scim_id, [
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
        create_user(context.connection, %{"userName" => "invited@example.com"})

      assert {:ok, %{state: :inactive}} =
               patch_user(context.connection, resource.scim_id, [
                 %{"op" => "replace", "path" => "active", "value" => "False"}
               ])

      assert OrganizationInvitations.all_pending(context.organization) == []
    end

    test "deactivating the last member is refused", context do
      resolved = materialized_admin(context)

      assert {:error, :last_member} =
               patch_user(context.connection, resolved.resource.scim_id, [
                 %{"op" => "replace", "value" => %{"active" => "False"}}
               ])

      assert Organizations.get_role(context.organization, context.admin) == "admin"
    end

    test "deactivating the last administrator is refused", context do
      insert(:organization_user,
        organization: context.organization,
        user: insert(:user),
        role: "read"
      )

      resolved = materialized_admin(context)

      assert {:error, :last_admin} =
               patch_user(context.connection, resolved.resource.scim_id, [
                 %{"op" => "replace", "path" => "active", "value" => false}
               ])

      assert Organizations.get_role(context.organization, context.admin) == "admin"
    end

    test "deactivating twice is idempotent", context do
      user = insert(:user)

      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => hd(user.emails).email})

      assert {:ok, %{state: :inactive}} = deactivate(context.connection, resource)
      assert {:ok, %{state: :inactive}} = deactivate(context.connection, resource)
    end

    test "reactivating claims a seat again with the provisioned role", context do
      user = insert(:user)

      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => hd(user.emails).email})

      {:ok, _resolved} = deactivate(context.connection, resource)
      refute Organizations.get_role(context.organization, user)

      assert {:ok, %{state: :member}} =
               patch_user(context.connection, resource.scim_id, [
                 %{"op" => "replace", "path" => "active", "value" => true}
               ])

      assert Organizations.get_role(context.organization, user) == "read"
      assert Seats.used(context.organization) == 2
    end

    test "a member removed by hand reads as inactive on the next request", context do
      user = insert(:user)

      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => hd(user.emails).email})

      :ok =
        Organizations.remove_member(context.organization, user, audit: audit_data(context.admin))

      assert {:ok, %{state: :inactive}} =
               SCIM.get_user(context.connection, resource.scim_id)
    end

    test "an accepted invitation repairs the handle to the member", context do
      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => "joiner@example.com"})

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
        create_user(context.connection, %{"userName" => email})

      assert {:ok, %{state: :inactive}} =
               replace_user(context.connection, resource.scim_id, %{
                 "userName" => email,
                 "active" => false
               })

      refute Organizations.get_role(context.organization, user)
    end

    test "renaming a member relabels without rebinding the account", context do
      user = insert(:user)

      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => hd(user.emails).email})

      assert {:ok, %{state: :member, resource: resource, user: same}} =
               replace_user(context.connection, resource.scim_id, %{
                 "userName" => "newlabel@example.com",
                 "active" => true
               })

      assert resource.user_name == "newlabel@example.com"
      assert same.id == user.id
    end

    test "renaming an invited person reinvites the new address", context do
      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => "old@example.com"})

      assert {:ok, %{state: :invited, resource: resource}} =
               replace_user(context.connection, resource.scim_id, %{
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
        create_user(context.connection, %{"userName" => email})

      assert :ok = delete_user(context.connection, resource.scim_id)
      refute Organizations.get_role(context.organization, user)
      assert {:error, :not_found} = SCIM.get_user(context.connection, resource.scim_id)

      assert {:ok, _resolved} = create_user(context.connection, %{"userName" => email})
    end

    test "deleting the last member is refused and keeps the handle", context do
      resolved = materialized_admin(context)

      assert {:error, :last_member} =
               delete_user(context.connection, resolved.resource.scim_id)

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

      listing = list_users(context.connection, 1, 2)
      assert listing.total == 4
      assert length(listing.resources) == 2

      rest = list_users(context.connection, 3, 2)
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

      listing = list_users(context.connection, 1, 100)
      user_names = Enum.map(listing.resources, & &1.resource.user_name)
      assert "work@corp.example.com" in user_names
    end

    test "filtering by userName materializes a current member exactly once", context do
      user = insert(:user)
      insert(:organization_user, organization: context.organization, user: user)
      email = hd(user.emails).email

      assert %{state: :member} = find_by_user_name(context.connection, email)
      assert %{state: :member} = find_by_user_name(context.connection, email)

      assert Repo.aggregate(Resource, :count) == 1
    end

    test "filtering by userName finds nothing for outsiders", context do
      outsider = insert(:user)

      assert find_by_user_name(context.connection, hd(outsider.emails).email) == nil
      assert Repo.aggregate(Resource, :count) == 0
    end

    test "filtering by externalId matches stored handles", context do
      {:ok, %{resource: resource}} =
        create_user(context.connection, %{
          "userName" => "ext@example.com",
          "externalId" => "okta-123"
        })

      assert %{resource: found} = SCIM.find_by_external_id(context.connection, "okta-123")
      assert found.id == resource.id
      assert SCIM.find_by_external_id(context.connection, "unknown") == nil
    end
  end

  describe "security review regressions" do
    test "a member matched by the address they authenticate with is deprovisioned", context do
      member = insert(:user)
      insert(:organization_user, organization: context.organization, user: member, role: "write")

      insert(:organization_sso_identity,
        connection: context.connection,
        organization: context.organization,
        user: member,
        provider_email: "Work@Corp.example.com"
      )

      # No verified copy of the work address on the Hex account; the identity is
      # what names them.
      assert %{state: :member, resource: resource} =
               find_by_user_name(context.connection, "work@corp.example.com")

      assert {:ok, %{state: :inactive}} = deactivate(context.connection, resource)
      refute Organizations.get_role(context.organization, member)
    end

    test "a member already holding a handle is relabeled rather than missed", context do
      member = insert(:user)
      insert(:organization_user, organization: context.organization, user: member, role: "write")

      # The first import binds their primary address.
      list_users(context.connection, 1, 100)

      insert(:organization_sso_identity,
        connection: context.connection,
        organization: context.organization,
        user: member,
        provider_email: "renamed@corp.example.com"
      )

      assert %{state: :member, resource: resource} =
               find_by_user_name(context.connection, "renamed@corp.example.com")

      assert resource.user_name == "renamed@corp.example.com"
      assert Repo.aggregate(from(r in Resource, where: r.user_id == ^member.id), :count) == 1
    end

    test "reactivating under a new name binds whoever accepts, not the old account",
         context do
      old = insert(:user)

      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => hd(old.emails).email})

      {:ok, _resolved} = deactivate(context.connection, resource)

      {:ok, _resolved} =
        replace_user(context.connection, resource.scim_id, %{
          "userName" => "successor@example.com",
          "active" => true
        })

      reloaded = Repo.get!(Resource, resource.id)
      refute reloaded.user_id

      successor = insert(:user)

      invitation =
        Repo.get!(OrganizationInvitation, reloaded.invitation_id) |> Repo.preload(:organization)

      {:ok, _member} =
        OrganizationInvitations.accept(invitation, successor, audit: audit_data(successor))

      assert {:ok, %{state: :inactive}} = deactivate(context.connection, reloaded)
      refute Organizations.get_role(context.organization, successor)
      refute Organizations.get_role(context.organization, old)
    end

    test "a deactivated handle keeps no pointer at the account it named", context do
      user = insert(:user)

      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => hd(user.emails).email})

      {:ok, _resolved} = deactivate(context.connection, resource)

      refute Repo.get!(Resource, resource.id).user_id
    end

    test "an invitation sent by hand does not survive the deprovisioning", context do
      user = insert(:user)
      email = hd(user.emails).email

      {:ok, _invitation} =
        OrganizationInvitations.invite(
          context.organization,
          %{"email" => email, "role" => "admin"},
          context.admin,
          audit: audit_data(context.admin)
        )

      {:ok, %{resource: resource}} = create_user(context.connection, %{"userName" => email})
      {:ok, _resolved} = deactivate(context.connection, resource)

      refute Organizations.get_role(context.organization, user)
      refute OrganizationInvitations.get_pending_by_email(context.organization, email)
    end

    test "a PUT that says nothing about active does not re-add a member", context do
      user = insert(:user)
      email = hd(user.emails).email

      {:ok, %{resource: resource}} = create_user(context.connection, %{"userName" => email})

      other = insert(:user)
      insert(:organization_user, organization: context.organization, user: other, role: "write")

      :ok =
        Organizations.remove_member(context.organization, user, audit: audit_data(context.admin))

      {:ok, _resolved} =
        replace_user(context.connection, resource.scim_id, %{"userName" => email})

      refute Organizations.get_role(context.organization, user)
    end

    test "joining through a verified address tells the person", context do
      user = insert(:user)

      {:ok, _resolved} =
        create_user(context.connection, %{"userName" => hd(user.emails).email})

      assert %OutboxEntry{category: "organization.member_added", recipients: [recipient]} =
               Repo.get_by!(OutboxEntry,
                 group_key: "organization-member-added:#{context.organization.id}:#{user.id}"
               )

      assert recipient == hd(user.emails).email
    end

    test "provisioning writes name the agent and its address", context do
      user = insert(:user)

      {:ok, _resolved} =
        create_user(context.connection, %{"userName" => hd(user.emails).email})

      rows = AuditLogs.all_by(context.organization)

      assert Enum.all?(rows, &(&1.user_agent == "SCIM"))
      assert Enum.all?(rows, &(&1.remote_ip == "198.51.100.4"))
      assert "sso.scim.resource.create" in Enum.map(rows, & &1.action)
      assert "organization.member.add" in Enum.map(rows, & &1.action)
    end

    test "a relabel leaves a record, since it decides what a reactivation binds",
         context do
      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => "before@example.com"})

      {:ok, _resolved} =
        replace_user(context.connection, resource.scim_id, %{"userName" => "after@example.com"})

      assert "sso.scim.resource.update" in Enum.map(
               AuditLogs.all_by(context.organization),
               & &1.action
             )
    end

    test "an unrecognized active value is refused rather than read as active", context do
      user = insert(:user)

      assert {:error, :invalid_value} =
               create_user(context.connection, %{
                 "userName" => hd(user.emails).email,
                 "active" => "0"
               })

      refute Organizations.get_role(context.organization, user)
    end

    test "attribute names and the schema URN are matched case-insensitively", context do
      user = insert(:user)

      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => hd(user.emails).email})

      other = insert(:user)
      insert(:organization_user, organization: context.organization, user: other, role: "write")

      assert {:ok, %{state: :inactive}} =
               patch_user(context.connection, resource.scim_id, [
                 %{
                   "op" => "Replace",
                   "path" => "urn:ietf:params:scim:schemas:core:2.0:User:ACTIVE",
                   "value" => "FALSE"
                 }
               ])

      refute Organizations.get_role(context.organization, user)
    end

    test "a value object with a differently cased key is applied", context do
      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => "cased@example.com"})

      assert {:ok, %{resource: renamed}} =
               patch_user(context.connection, resource.scim_id, [
                 %{"op" => "replace", "value" => %{"username" => "recased@example.com"}}
               ])

      assert renamed.user_name == "recased@example.com"
    end

    test "malformed operations are refused rather than raised", context do
      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => "malformed@example.com"})

      for operation <- [
            %{"op" => %{}, "path" => "active", "value" => false},
            %{"op" => "replace", "path" => 1, "value" => false},
            %{"path" => "active", "value" => false}
          ] do
        assert {:error, :invalid_path} =
                 patch_user(context.connection, resource.scim_id, [operation])
      end
    end

    test "a PATCH longer than the cap is refused before anything is written", context do
      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => "capped@example.com"})

      operations =
        for index <- 1..(SCIM.max_operations() + 1) do
          %{"op" => "replace", "path" => "userName", "value" => "capped#{index}@example.com"}
        end

      assert {:error, :too_many_operations} =
               patch_user(context.connection, resource.scim_id, operations)

      assert Repo.get!(Resource, resource.id).user_name == "capped@example.com"
    end

    test "one externalId on two handles answers rather than failing", context do
      {:ok, _first} =
        create_user(context.connection, %{
          "userName" => "rehire1@example.com",
          "externalId" => "shared"
        })

      {:ok, _second} =
        create_user(context.connection, %{
          "userName" => "rehire2@example.com",
          "externalId" => "shared"
        })

      assert %{resource: %Resource{user_name: "rehire1@example.com"}} =
               SCIM.find_by_external_id(context.connection, "shared")
    end

    test "removing someone who is not a member is not the last-member refusal", context do
      outsider = insert(:user)

      assert :ok =
               Organizations.remove_member(context.organization, outsider,
                 audit: audit_data(context.admin)
               )
    end
  end

  describe "review regressions" do
    test "deactivating a member also retires a pending invitation for the handle", context do
      {:ok, %{state: :invited, resource: resource}} =
        create_user(context.connection, %{"userName" => "late@example.com"})

      user = insert(:user, emails: [build(:email, email: "late@example.com")])
      insert(:organization_user, organization: context.organization, user: user)

      assert {:ok, %{state: :member}} = SCIM.get_user(context.connection, resource.scim_id)

      assert {:ok, %{state: :inactive}} = deactivate(context.connection, resource)

      refute Organizations.get_role(context.organization, user)
      assert OrganizationInvitations.all_pending(context.organization) == []
    end

    test "deactivating after the invitation was accepted removes the member", context do
      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => "accepted@example.com"})

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

      listing = list_users(context.connection, 1, 100)

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
        create_user(context.connection, %{"userName" => email_a})

      {:ok, _resolved} = deactivate(context.connection, resource)

      assert {:ok, %{state: :member, resource: resource, user: activated}} =
               patch_user(context.connection, resource.scim_id, [
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
        create_user(context.connection, %{"userName" => "old@example.com"})

      {:ok, _other} = create_user(context.connection, %{"userName" => "taken@example.com"})

      assert {:error, :uniqueness} =
               patch_user(context.connection, resource.scim_id, [
                 %{"op" => "replace", "path" => "userName", "value" => "taken@example.com"}
               ])

      assert {:ok, %{state: :invited, resource: resource}} =
               SCIM.get_user(context.connection, resource.scim_id)

      assert resource.user_name == "old@example.com"

      emails =
        OrganizationInvitations.all_pending(context.organization) |> Enum.map(& &1.email)

      assert "old@example.com" in emails
    end

    test "a refused operation rolls back the whole PATCH", context do
      user = insert(:user)

      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => hd(user.emails).email})

      assert {:error, :invalid_path} =
               patch_user(context.connection, resource.scim_id, [
                 %{"op" => "replace", "path" => "active", "value" => false},
                 %{"op" => "remove", "path" => "userName"}
               ])

      assert Organizations.get_role(context.organization, user) == "read"
      assert {:ok, %{state: :member}} = SCIM.get_user(context.connection, resource.scim_id)
    end

    test "a PATCH refused partway through leaves the earlier operations unapplied",
         context do
      user = insert(:user)

      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => hd(user.emails).email})

      {:ok, _other} = create_user(context.connection, %{"userName" => "taken@example.com"})

      assert {:error, :uniqueness} =
               patch_user(context.connection, resource.scim_id, [
                 %{"op" => "replace", "path" => "active", "value" => false},
                 %{"op" => "replace", "path" => "userName", "value" => "taken@example.com"}
               ])

      assert Organizations.get_role(context.organization, user) == "read"
    end

    test "a create refused on its attributes leaves no invitation behind", context do
      assert {:error, %Ecto.Changeset{}} =
               create_user(context.connection, %{
                 "userName" => "nobody@example.com",
                 "externalId" => String.duplicate("x", 1_025)
               })

      assert OrganizationInvitations.all_pending(context.organization) == []
      refute Repo.get_by(OutboxEntry, category: "organization.invitation")
    end

    test "deactivating an inactive handle retires an invitation sent by hand", context do
      user = insert(:user)
      email = hd(user.emails).email

      {:ok, %{resource: resource}} = create_user(context.connection, %{"userName" => email})
      {:ok, %{state: :inactive}} = deactivate(context.connection, resource)

      {:ok, _invitation} =
        OrganizationInvitations.invite(
          context.organization,
          %{"email" => email, "role" => "write"},
          context.admin,
          audit: audit_data(context.admin)
        )

      assert {:ok, %{state: :inactive}} = deactivate(context.connection, resource)
      assert OrganizationInvitations.all_pending(context.organization) == []
    end

    test "an invitation the last member accepted makes the handle theirs, and the guard holds",
         context do
      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => "admin-alias@example.com"})

      invitation =
        Repo.get!(OrganizationInvitation, resource.invitation_id)
        |> Repo.preload(:organization)

      {:ok, :already_member} =
        OrganizationInvitations.accept(invitation, context.admin,
          audit: audit_data(context.admin)
        )

      assert {:ok, %{state: :member, user: %{id: admin_id}}} =
               SCIM.get_user(context.connection, resource.scim_id)

      assert admin_id == context.admin.id

      assert {:error, :last_member} = deactivate(context.connection, resource)
      assert Organizations.get_role(context.organization, context.admin) == "admin"
    end

    test "the import lists a member added after another was removed by hand", context do
      leaver = insert(:user)
      insert(:organization_user, organization: context.organization, user: leaver)

      assert Enum.count(list_users(context.connection, 1, 100).resources) == 2

      :ok =
        Organizations.remove_member(context.organization, leaver,
          audit: audit_data(context.admin)
        )

      joiner = insert(:user)
      insert(:organization_user, organization: context.organization, user: joiner)

      listing = list_users(context.connection, 1, 100)
      assert Enum.any?(listing.resources, &(&1.user && &1.user.id == joiner.id))
    end

    test "a PATCH that sets active to null is refused", context do
      user = insert(:user)

      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => hd(user.emails).email})

      assert {:error, :invalid_value} =
               patch_user(context.connection, resource.scim_id, [
                 %{"op" => "replace", "path" => "active", "value" => nil}
               ])

      assert {:error, :invalid_value} =
               patch_user(context.connection, resource.scim_id, [
                 %{"op" => "replace", "value" => %{"active" => nil}}
               ])

      assert Organizations.get_role(context.organization, user) == "read"
    end

    test "an accepted invitation binds the handle in the acceptance itself", context do
      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => "joiner@example.com"})

      invitation =
        Repo.get!(OrganizationInvitation, resource.invitation_id)
        |> Repo.preload(:organization)

      joiner = insert(:user)

      {:ok, _organization_user} =
        OrganizationInvitations.accept(invitation, joiner, audit: audit_data(joiner))

      assert Repo.get!(Resource, resource.id).user_id == joiner.id

      # An import between the acceptance and the next read must not hand the
      # account to a second row.
      listing = list_users(context.connection, 1, 100)
      assert Enum.count(listing.resources, &(&1.user && &1.user.id == joiner.id)) == 1

      assert {:ok, %{state: :inactive}} = deactivate(context.connection, resource)
      refute Organizations.get_role(context.organization, joiner)
    end

    test "deactivating after a rename removes the member the new name matches", context do
      leaver = insert(:user)
      stayer = insert(:user)
      insert(:organization_user, organization: context.organization, user: stayer)

      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => hd(leaver.emails).email})

      :ok =
        Organizations.remove_member(context.organization, leaver,
          audit: audit_data(context.admin)
        )

      assert {:ok, %{state: :inactive}} =
               patch_user(context.connection, resource.scim_id, [
                 %{"op" => "replace", "path" => "userName", "value" => hd(stayer.emails).email},
                 %{"op" => "replace", "path" => "active", "value" => false}
               ])

      refute Organizations.get_role(context.organization, stayer)
      assert {:ok, %{state: :inactive}} = SCIM.get_user(context.connection, resource.scim_id)
    end

    test "deactivating a handle removes everyone its address names", context do
      bound = insert(:user)
      named = insert(:user)
      insert(:organization_user, organization: context.organization, user: named)

      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => hd(bound.emails).email})

      assert {:ok, %{state: :inactive}} =
               patch_user(context.connection, resource.scim_id, [
                 %{"op" => "replace", "path" => "userName", "value" => hd(named.emails).email},
                 %{"op" => "replace", "path" => "active", "value" => false}
               ])

      refute Organizations.get_role(context.organization, bound)
      refute Organizations.get_role(context.organization, named)
      assert {:ok, %{state: :inactive}} = SCIM.get_user(context.connection, resource.scim_id)
    end

    test "an accepted invitation does not outlive a rename of the inactive handle", context do
      acceptor = insert(:user)
      named = insert(:user)
      insert(:organization_user, organization: context.organization, user: named)

      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => "work@example.com"})

      invitation =
        Repo.get!(OrganizationInvitation, resource.invitation_id)
        |> Repo.preload(:organization)

      {:ok, _organization_user} =
        OrganizationInvitations.accept(invitation, acceptor, audit: audit_data(acceptor))

      :ok =
        Organizations.remove_member(context.organization, acceptor,
          audit: audit_data(context.admin)
        )

      assert {:ok, %{state: :inactive}} =
               patch_user(context.connection, resource.scim_id, [
                 %{"op" => "replace", "path" => "userName", "value" => hd(named.emails).email},
                 %{"op" => "replace", "path" => "active", "value" => false}
               ])

      refute Organizations.get_role(context.organization, named)
      assert {:ok, %{state: :inactive}} = SCIM.get_user(context.connection, resource.scim_id)
    end

    test "deactivating an address several identities share removes each of them", context do
      connection_row = Repo.get!(Hexpm.Accounts.SSO.Connection, context.connection.id)

      sharers =
        for n <- 1..5 do
          user = insert(:user)
          insert(:organization_user, organization: context.organization, user: user)

          insert(:organization_sso_identity,
            organization: context.organization,
            connection: connection_row,
            user: user,
            subject: "sharer-#{n}",
            provider_email: "shared@example.com"
          )

          user
        end

      {:ok, %{resource: resource}} =
        create_user(context.connection, %{"userName" => "handle@example.com", "active" => false})

      assert {:ok, %{state: :inactive}} =
               patch_user(context.connection, resource.scim_id, [
                 %{"op" => "replace", "path" => "userName", "value" => "shared@example.com"},
                 %{"op" => "replace", "path" => "active", "value" => false}
               ])

      for user <- sharers, do: refute(Organizations.get_role(context.organization, user))
      assert {:ok, %{state: :inactive}} = SCIM.get_user(context.connection, resource.scim_id)
    end

    test "the import survives two identities sharing a mixed-case address", context do
      connection_row = Repo.get!(Hexpm.Accounts.SSO.Connection, context.connection.id)

      for n <- 1..2 do
        user = insert(:user)
        insert(:organization_user, organization: context.organization, user: user)

        insert(:organization_sso_identity,
          organization: context.organization,
          connection: connection_row,
          user: user,
          subject: "sharer-#{n}",
          provider_email: "Shared@Example.com"
        )
      end

      listing = list_users(context.connection, 1, 100)
      assert Enum.count(listing.resources, &(&1.resource.user_name == "shared@example.com")) == 1
    end

    test "filter values past the column bounds match nothing", context do
      assert find_by_user_name(context.connection, String.duplicate("a", 250) <> "@x.io") ==
               nil

      assert SCIM.find_by_external_id(context.connection, String.duplicate("x", 1_025)) == nil
    end
  end

  defp deactivate(connection, resource) do
    patch_user(connection, resource.scim_id, [
      %{"op" => "replace", "path" => "active", "value" => false}
    ])
  end

  # The provisioning agent is the actor on every write.
  defp audit(connection), do: AuditLogs.scim(connection.organization, "198.51.100.4")

  defp list_users(connection, start_index, count),
    do: SCIM.list_users(connection, start_index, count, audit: audit(connection))

  defp find_by_user_name(connection, user_name),
    do: SCIM.find_by_user_name(connection, user_name, audit: audit(connection))

  defp create_user(connection, params),
    do: SCIM.create_user(connection, params, audit: audit(connection))

  defp replace_user(connection, scim_id, params),
    do: SCIM.replace_user(connection, scim_id, params, audit: audit(connection))

  defp patch_user(connection, scim_id, operations),
    do: SCIM.patch_user(connection, scim_id, operations, audit: audit(connection))

  defp delete_user(connection, scim_id),
    do: SCIM.delete_user(connection, scim_id, audit: audit(connection))

  defp materialized_admin(context) do
    find_by_user_name(context.connection, hd(context.admin.emails).email)
  end

  defp seats_full(organization) do
    filler = insert(:user)
    insert(:organization_user, organization: organization, user: filler)

    organization
    |> Ecto.Changeset.change(billing_seats: 2)
    |> Repo.update!()
  end

  defp require_tfa(organization) do
    app_env(:hexpm, :organization_tfa, mode: :enabled, beta_organizations: [])

    organization
    |> Ecto.Changeset.change(tfa_required_at: DateTime.add(DateTime.utc_now(), 14 * 86_400))
    |> Repo.update!()
  end
end
