defmodule Hexpm.Accounts.OrganizationInvitationsTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.{AuditLogs, OrganizationInvitations, Organizations}
  alias Hexpm.Emails.OutboxEntry

  setup do
    organization = insert(:organization, billing_seats: 3)
    admin = insert(:user)
    insert(:organization_user, organization: organization, user: admin, role: "admin")

    %{organization: organization, admin: admin}
  end

  describe "OrganizationInvitation.changeset/2" do
    test "bounds the email address in bytes", %{organization: organization} do
      at_cap = combining_string(250) <> "@b.co"
      assert byte_size(at_cap) == 255
      assert invitation_changeset(organization, at_cap).valid?

      changeset = invitation_changeset(organization, combining_string(252) <> "@b.co")
      assert errors_on(changeset).email == "should be at most 255 byte(s)"
    end

    defp invitation_changeset(organization, email) do
      Hexpm.Accounts.OrganizationInvitation.changeset(
        %Hexpm.Accounts.OrganizationInvitation{},
        %{
          organization_id: organization.id,
          email: email,
          role: "read",
          token_hash: "hash",
          expires_at: DateTime.utc_now()
        }
      )
    end
  end

  describe "invite/4" do
    test "sends a link the recipient can use", %{organization: organization, admin: admin} do
      assert {:ok, invitation} = invite(organization, admin, "newcomer@example.com")

      assert invitation.email == "newcomer@example.com"
      assert invitation.role == "read"
      assert invitation.invited_by_user_id == admin.id

      assert %OutboxEntry{category: "organization.invitation", email: email} =
               Repo.get_by!(OutboxEntry, group_key: "organization-invitation:#{invitation.id}")

      assert email["to"] == [%{"name" => "", "address" => "newcomer@example.com"}]

      assert OrganizationInvitations.get_pending_by_token(invitation.raw_token).id ==
               invitation.id
    end

    test "stores only the hash of the token", %{organization: organization, admin: admin} do
      assert {:ok, invitation} = invite(organization, admin, "newcomer@example.com")

      assert invitation.token_hash == :crypto.hash(:sha256, invitation.raw_token)
      refute invitation.token_hash == invitation.raw_token
    end

    test "normalizes the address", %{organization: organization, admin: admin} do
      assert {:ok, invitation} = invite(organization, admin, "  Newcomer@Example.COM ")
      assert invitation.email == "newcomer@example.com"
    end

    test "refuses an address that already belongs to a member", %{
      organization: organization,
      admin: admin
    } do
      member = insert(:user)
      insert(:organization_user, organization: organization, user: member)

      assert {:error, :already_member} = invite(organization, admin, user_email(member))
    end

    test "invites an address that belongs to a non-member account", %{
      organization: organization,
      admin: admin
    } do
      outsider = insert(:user)

      assert {:ok, _invitation} = invite(organization, admin, user_email(outsider))
    end

    test "refuses a second pending invitation for the same address", %{
      organization: organization,
      admin: admin
    } do
      assert {:ok, _invitation} = invite(organization, admin, "newcomer@example.com")
      assert {:error, changeset} = invite(organization, admin, "newcomer@example.com")
      assert errors_on(changeset).email == "has already been invited"
    end

    test "allows inviting an address again after the first was revoked", %{
      organization: organization,
      admin: admin
    } do
      {:ok, invitation} = invite(organization, admin, "newcomer@example.com")

      {:ok, _} =
        OrganizationInvitations.revoke(organization, invitation, audit: audit_data(admin))

      assert {:ok, _invitation} = invite(organization, admin, "newcomer@example.com")
    end

    test "re-inviting an address whose invitation expired reissues it", %{
      organization: organization,
      admin: admin
    } do
      {:ok, first} = invite(organization, admin, "newcomer@example.com")

      first
      |> Ecto.Changeset.change(
        expires_at: DateTime.add(DateTime.utc_now(), -1, :second),
        sent_at: DateTime.add(DateTime.utc_now(), -8 * 24 * 60 * 60, :second)
      )
      |> Repo.update!()

      # The expired row still holds the one-per-address slot and no read path
      # shows it, so refusing here would be a dead end with nothing to act on.
      assert OrganizationInvitations.all_pending(organization) == []
      assert {:ok, second} = invite(organization, admin, "newcomer@example.com")

      assert second.id == first.id
      refute second.raw_token == first.raw_token
      refute OrganizationInvitations.get_pending_by_token(first.raw_token)
      assert OrganizationInvitations.get_pending_by_token(second.raw_token)
      assert [_invitation] = OrganizationInvitations.all_pending(organization)
    end

    test "re-inviting an expired address stores the role asked for", %{
      organization: organization,
      admin: admin
    } do
      {:ok, first} = invite(organization, admin, "newcomer@example.com", "read")
      expire(first)

      assert {:ok, second} = invite(organization, admin, "newcomer@example.com", "admin")

      assert second.role == "admin"
      assert Repo.get!(Hexpm.Accounts.OrganizationInvitation, first.id).role == "admin"
    end

    test "re-inviting an expired address refuses a role that does not exist", %{
      organization: organization,
      admin: admin
    } do
      {:ok, first} = invite(organization, admin, "newcomer@example.com", "read")
      expire(first)

      assert {:error, changeset} =
               invite(organization, admin, "newcomer@example.com", "Visit example.com")

      assert errors_on(changeset).role == "is invalid"
      assert Repo.get!(Hexpm.Accounts.OrganizationInvitation, first.id).role == "read"

      assert Repo.aggregate(
               from(e in OutboxEntry, where: e.category == "organization.invitation"),
               :count
             ) == 1
    end

    test "stops mailing an address five invitations reached in the last day", %{admin: admin} do
      invite_from_other_organizations(admin, "target@example.com", 5)

      assert {:error, :too_many_invitations} =
               invite(insert(:organization), admin, "target@example.com")

      assert Repo.aggregate(
               from(e in OutboxEntry, where: e.category == "organization.invitation"),
               :count
             ) == 5
    end

    test "counts only the invitations of the last day", %{admin: admin} do
      invite_from_other_organizations(admin, "target@example.com", 5)
      day_ago = DateTime.add(DateTime.utc_now(), -25 * 60 * 60)

      Repo.update_all(Hexpm.Accounts.OrganizationInvitation,
        set: [updated_at: day_ago, sent_at: day_ago]
      )

      assert {:ok, _invitation} = invite(insert(:organization), admin, "target@example.com")
    end

    test "stops an inviter after fifty invitations in an hour", %{
      organization: organization,
      admin: admin
    } do
      for index <- 1..50 do
        assert {:ok, _invitation} = invite(organization, admin, "person#{index}@example.com")
      end

      assert {:error, :too_many_invitations} =
               invite(organization, admin, "person51@example.com")
    end

    test "stops provisioning after five hundred invitations to an organization in a day", %{
      organization: organization,
      admin: admin
    } do
      insert_invitations(organization, nil, 499)
      assert {:ok, _invitation} = provision(organization, admin, "person500@example.com")

      assert {:error, :too_many_invitations} =
               provision(organization, admin, "person501@example.com")
    end

    test "counts provisioning that reissues an invitation a person sent", %{
      organization: organization,
      admin: admin
    } do
      {:ok, lapsed} = invite(organization, admin, "lapsed@example.com")
      expire(lapsed)
      insert_invitations(organization, nil, 499)

      assert {:ok, reissued} = provision(organization, admin, "lapsed@example.com")
      assert reissued.id == lapsed.id
      assert reissued.invited_by_user_id == nil

      assert {:error, :too_many_invitations} =
               provision(organization, admin, "person501@example.com")
    end

    test "counts provisioning invitations of the organization in the last day only", %{
      admin: admin
    } do
      insert_invitations(insert(:organization), nil, 500)
      assert {:ok, _invitation} = provision(insert(:organization), admin, "first@example.com")

      invited_by_a_person = insert(:organization)
      insert_invitations(invited_by_a_person, admin, 500)
      assert {:ok, _invitation} = provision(invited_by_a_person, admin, "second@example.com")

      day_ago = DateTime.add(DateTime.utc_now(), -25 * 60 * 60)
      provisioned_yesterday = insert(:organization)
      insert_invitations(provisioned_yesterday, nil, 500, day_ago)
      assert {:ok, _invitation} = provision(provisioned_yesterday, admin, "third@example.com")
    end

    test "rejects an address that is not one", %{organization: organization, admin: admin} do
      assert {:error, changeset} = invite(organization, admin, "not-an-address")
      assert errors_on(changeset).email == "is not a valid email"
    end

    test "accepts an address without a dot in the domain", %{
      organization: organization,
      admin: admin
    } do
      assert {:ok, _invitation} = invite(organization, admin, "person@localhost")
    end

    test "audits the invitation without exposing the token", %{
      organization: organization,
      admin: admin
    } do
      {:ok, invitation} = invite(organization, admin, "newcomer@example.com")

      assert audit_log =
               Enum.find(
                 AuditLogs.all_by(admin),
                 &(&1.action == "organization.invitation.create")
               )

      assert audit_log.params["invitation"]["email"] == "newcomer@example.com"
      refute inspect(audit_log.params) =~ invitation.raw_token
    end
  end

  describe "invite_user/5" do
    test "invites the account and mails its primary address", %{
      organization: organization,
      admin: admin
    } do
      user = insert(:user)

      assert {:ok, invitation} = invite_user(organization, admin, user, "write")

      assert invitation.user_id == user.id
      assert invitation.role == "write"
      assert invitation.email == nil
      assert invitation.token_hash == nil
      refute Organizations.get_role(organization, user)

      assert %OutboxEntry{category: "organization.invitation", email: email} =
               Repo.get_by!(OutboxEntry, group_key: "organization-invitation:#{invitation.id}")

      assert email["to"] == [%{"name" => user.username, "address" => user_email(user)}]
      assert email["text_body"] =~ "/dashboard/invitations"
    end

    test "refuses a user whose primary email is unverified", %{
      organization: organization,
      admin: admin
    } do
      user = insert(:user, emails: [build(:email, verified: false)])

      assert {:error, :unverified_primary_email} = invite_user(organization, admin, user)
      assert OrganizationInvitations.all_pending(organization) == []
    end

    test "a verified secondary email does not stand in for the primary", %{
      organization: organization,
      admin: admin
    } do
      user =
        insert(:user,
          emails: [
            build(:email, verified: false),
            build(:email, primary: false, public: false, gravatar: false)
          ]
        )

      assert {:error, :unverified_primary_email} = invite_user(organization, admin, user)
    end

    test "refuses an organization", %{organization: organization, admin: admin} do
      other = insert(:organization)

      assert {:error, :organization_user} = invite_user(organization, admin, other.user)
    end

    test "refuses a member", %{organization: organization, admin: admin} do
      assert {:error, :already_member} = invite_user(organization, admin, admin)
    end

    test "refuses a second pending invitation for the same account", %{
      organization: organization,
      admin: admin
    } do
      user = insert(:user)

      assert {:ok, _invitation} = invite_user(organization, admin, user)
      assert {:error, :invitation_cooldown} = invite_user(organization, admin, user)
    end

    test "stops mailing an account five invitations reached in the last day", %{admin: admin} do
      user = insert(:user)

      for _ <- 1..5 do
        assert {:ok, _invitation} = invite_user(insert(:organization), admin, user)
      end

      assert {:error, :too_many_invitations} = invite_user(insert(:organization), admin, user)
    end

    test "counts invitations to accounts against the inviter", %{
      organization: organization,
      admin: admin
    } do
      for index <- 1..50 do
        assert {:ok, _invitation} = invite(organization, admin, "person#{index}@example.com")
      end

      assert {:error, :too_many_invitations} = invite_user(organization, admin, insert(:user))
    end

    test "re-inviting an account whose invitation expired reissues it", %{
      organization: organization,
      admin: admin
    } do
      user = insert(:user)
      {:ok, first} = invite_user(organization, admin, user)
      expire(first)

      assert OrganizationInvitations.all_pending_for_user(user) == []
      assert {:ok, second} = invite_user(organization, admin, user, "admin")
      assert second.id == first.id
      assert second.role == "admin"
      assert [%{id: id}] = OrganizationInvitations.all_pending_for_user(user)
      assert id == first.id
    end

    test "does not mail an account that opted out but still shows it the invitation", %{
      organization: organization,
      admin: admin
    } do
      user = insert(:user, optional_emails: %{"organization_invite" => false})

      assert {:ok, invitation} = invite_user(organization, admin, user)
      assert Repo.all(OutboxEntry) == []
      assert [%{id: id}] = OrganizationInvitations.all_pending_for_user(user)
      assert id == invitation.id
    end

    test "audits the invited account", %{organization: organization, admin: admin} do
      user = insert(:user)
      {:ok, invitation} = invite_user(organization, admin, user)

      assert audit_log =
               Enum.find(
                 AuditLogs.all_by(admin),
                 &(&1.action == "organization.invitation.create")
               )

      assert audit_log.params["invitation"] == %{
               "id" => invitation.id,
               "email" => nil,
               "role" => "read",
               "user" => %{"id" => user.id, "username" => user.username}
             }
    end
  end

  describe "decline/3" do
    test "declining preserves the expiry and the cooldown starts when sent", %{
      organization: organization,
      admin: admin
    } do
      user = insert(:user)
      {:ok, invitation} = invite_user(organization, admin, user)
      yesterday = DateTime.add(DateTime.utc_now(), -24 * 60 * 60 - 1)
      invitation = invitation |> Ecto.Changeset.change(sent_at: yesterday) |> Repo.update!()

      assert {:ok, declined} = decline(invitation, user)
      assert declined.declined_at
      assert OrganizationInvitations.all_pending_for_user(user) == []
      assert OrganizationInvitations.all_pending(organization) == []
      assert declined.expires_at == invitation.expires_at
      assert declined.sent_at == invitation.sent_at

      assert {:ok, reissued} = invite_user(organization, admin, user)
      assert reissued.id == invitation.id
      assert reissued.declined_at == nil
      assert [_pending] = OrganizationInvitations.all_pending_for_user(user)
    end

    test "leaves other organizations free to invite the account", %{
      organization: organization,
      admin: admin
    } do
      user = insert(:user)
      {:ok, invitation} = invite_user(organization, admin, user)
      {:ok, _declined} = decline(invitation, user)

      assert {:ok, _invitation} = invite_user(insert(:organization), admin, user)
    end

    test "takes the invitation mail that hasn't gone out with it", %{
      organization: organization,
      admin: admin
    } do
      user = insert(:user)
      {:ok, invitation} = invite_user(organization, admin, user)
      assert [_mail] = Repo.all(OutboxEntry.undelivered())

      {:ok, _declined} = decline(invitation, user)

      assert Repo.all(OutboxEntry) == []
    end

    test "only the invited account can decline", %{organization: organization, admin: admin} do
      user = insert(:user)
      {:ok, invitation} = invite_user(organization, admin, user)

      assert {:error, :invitation_unavailable} = decline(invitation, insert(:user))
      assert [_pending] = OrganizationInvitations.all_pending_for_user(user)
    end

    test "an invitation sent to an address can't be declined", %{
      organization: organization,
      admin: admin
    } do
      {:ok, invitation} = invite(organization, admin, "newcomer@example.com")

      assert {:error, :invitation_unavailable} = decline(invitation, insert(:user))
    end

    test "audits the decline", %{organization: organization, admin: admin} do
      user = insert(:user)
      {:ok, invitation} = invite_user(organization, admin, user)
      {:ok, _declined} = decline(invitation, user)

      assert audit_log =
               Enum.find(
                 AuditLogs.all_by(user),
                 &(&1.action == "organization.invitation.decline")
               )

      assert audit_log.params["invitation"]["user"]["username"] == user.username
      assert audit_log.params["organization"]["name"] == organization.name
    end
  end

  describe "restoring declined invitations" do
    test "restores without extending the expiry or sending mail", %{
      organization: organization,
      admin: admin
    } do
      user = insert(:user)
      {:ok, invitation} = invite_user(organization, admin, user, "write")
      {:ok, declined} = decline(invitation, user)

      assert {:ok, restored} = restore(declined, user)
      assert restored.declined_at == nil
      assert restored.expires_at == invitation.expires_at
      assert restored.sent_at == invitation.sent_at
      assert [%{id: id}] = OrganizationInvitations.all_pending_for_user(user)
      assert id == invitation.id
      assert Repo.all(OutboxEntry) == []
      assert {:error, :invitation_cooldown} = invite_user(organization, admin, user)
      assert {:ok, membership} = accept(restored, user)
      assert membership.role == "write"
      assert Enum.any?(AuditLogs.all_by(user), &(&1.action == "organization.invitation.restore"))
    end

    test "refuses another account, an expired invitation, and a revoked invitation", %{
      organization: organization,
      admin: admin
    } do
      user = insert(:user)
      {:ok, invitation} = invite_user(organization, admin, user)
      {:ok, declined} = decline(invitation, user)
      assert {:error, :invitation_unavailable} = restore(declined, admin)

      {:ok, revoked} =
        OrganizationInvitations.revoke(organization, declined, audit: audit_data(admin))

      assert {:error, :invitation_unavailable} = restore(revoked, user)

      other = insert(:user)
      {:ok, invitation} = invite_user(organization, admin, other)
      {:ok, declined} = decline(invitation, other)
      expire(declined)
      assert {:error, :invitation_unavailable} = restore(declined, other)
    end

    test "cannot restore an accepted invitation or an email invitation", %{
      organization: organization,
      admin: admin
    } do
      user = insert(:user)
      {:ok, invitation} = invite_user(organization, admin, user)
      assert {:error, :invitation_unavailable} = restore(invitation, user)
      {:ok, _membership} = accept(invitation, user)
      assert {:error, :invitation_unavailable} = restore(invitation, user)
      {:ok, email_invitation} = invite(insert(:organization), admin, "new@example.com")
      assert {:error, :invitation_unavailable} = restore(email_invitation, user)
    end
  end

  describe "organization invitation blocks" do
    test "blocks account and email invitations until the recipient unblocks", %{
      organization: organization,
      admin: admin
    } do
      user = insert(:user)
      {:ok, invitation} = invite_user(organization, admin, user)
      assert {:ok, _invitation} = block(invitation, user)
      assert {:ok, _invitation} = block(invitation, user)
      assert [blocked] = OrganizationInvitations.all_blocks_for_user(user)
      assert blocked.organization_id == organization.id
      assert OrganizationInvitations.all_pending_for_user(user) == []
      assert Repo.all(OutboxEntry) == []
      assert {:error, :blocked} = invite_user(organization, admin, user)
      assert {:error, :blocked} = invite(organization, admin, user_email(user))
      assert {:error, :invitation_unavailable} = restore(invitation, user)

      assert {:error, :invitation_unavailable} =
               OrganizationInvitations.unblock(blocked, admin, audit: audit_data(admin))

      assert {:ok, _invitation} = invite_user(insert(:organization), admin, user)

      assert {:ok, _block} =
               OrganizationInvitations.unblock(blocked, user, audit: audit_data(user))

      assert OrganizationInvitations.all_blocks_for_user(user) == []
      assert {:ok, _restored} = restore(invitation, user)
      assert Enum.any?(AuditLogs.all_by(user), &(&1.action == "organization.invitation.block"))
      assert Enum.any?(AuditLogs.all_by(user), &(&1.action == "organization.invitation.unblock"))
    end

    test "a block survives invitation expiry and deletion", %{
      organization: organization,
      admin: admin
    } do
      user = insert(:user)
      {:ok, invitation} = invite_user(organization, admin, user)
      {:ok, _blocked} = block(invitation, user)
      expire(invitation)
      Repo.delete!(invitation)
      assert {:error, :blocked} = invite_user(organization, admin, user)
      assert [blocked] = OrganizationInvitations.all_blocks_for_user(user)

      assert {:ok, _block} =
               OrganizationInvitations.unblock(blocked, user, audit: audit_data(user))

      assert {:ok, _invitation} = invite_user(organization, admin, user)
    end

    test "only the recipient can block and only while the invitation is available", %{
      organization: organization,
      admin: admin
    } do
      user = insert(:user)
      {:ok, invitation} = invite_user(organization, admin, user)
      assert {:error, :invitation_unavailable} = block(invitation, admin)
      {:ok, declined} = decline(invitation, user)
      assert {:ok, _invitation} = block(declined, user)

      other = insert(:user)
      {:ok, expired} = invite_user(organization, admin, other)
      expire(expired)
      assert {:error, :invitation_unavailable} = block(expired, other)
      assert OrganizationInvitations.all_blocks_for_user(other) == []
    end
  end

  describe "account resend cooldown" do
    test "declining and revoking can't permit another invitation within 24 hours", %{
      organization: organization,
      admin: admin
    } do
      user = insert(:user)
      {:ok, invitation} = invite_user(organization, admin, user)
      {:ok, declined} = decline(invitation, user)
      assert {:error, :invitation_cooldown} = invite_user(organization, admin, user)
      assert {:error, :invitation_cooldown} = invite(organization, admin, user_email(user))

      {:ok, _revoked} =
        OrganizationInvitations.revoke(organization, declined, audit: audit_data(admin))

      assert {:error, :invitation_cooldown} = invite_user(organization, admin, user)
      assert Repo.all(OutboxEntry) == []
    end

    test "email invitations count toward the same account cooldown", %{
      organization: organization,
      admin: admin
    } do
      user = insert(:user)
      {:ok, invitation} = invite(organization, admin, user_email(user))

      {:ok, _invitation} =
        OrganizationInvitations.revoke(organization, invitation, audit: audit_data(admin))

      assert {:error, :invitation_cooldown} = invite_user(organization, admin, user)
    end
  end

  defp restore(invitation, user) do
    OrganizationInvitations.restore(Repo.preload(invitation, :organization), user,
      audit: audit_data(user)
    )
  end

  defp block(invitation, user) do
    OrganizationInvitations.block(Repo.preload(invitation, :organization), user,
      audit: audit_data(user)
    )
  end

  describe "accept/3" do
    test "joins the invited account", %{organization: organization, admin: admin} do
      user = insert(:user)
      {:ok, invitation} = invite_user(organization, admin, user, "write")

      assert {:ok, organization_user} = accept(invitation, user)
      assert organization_user.role == "write"
      assert Organizations.get_role(organization, user) == "write"
      assert OrganizationInvitations.all_pending_for_user(user) == []
    end

    test "refuses any account other than the invited one", %{
      organization: organization,
      admin: admin
    } do
      user = insert(:user)
      other = insert(:user)
      {:ok, invitation} = invite_user(organization, admin, user)

      assert {:error, :invitation_unavailable} = accept(invitation, other)
      refute Organizations.get_role(organization, other)
      assert [_pending] = OrganizationInvitations.all_pending_for_user(user)
    end

    test "refuses an invitation the account declined", %{
      organization: organization,
      admin: admin
    } do
      user = insert(:user)
      {:ok, invitation} = invite_user(organization, admin, user)
      {:ok, _declined} = decline(invitation, user)

      assert {:error, :invitation_unavailable} = accept(invitation, user)
      refute Organizations.get_role(organization, user)
    end

    test "joins the signed-in account with the invited role", %{
      organization: organization,
      admin: admin
    } do
      {:ok, invitation} = invite(organization, admin, "newcomer@example.com", "write")
      newcomer = insert(:user)

      assert {:ok, organization_user} = accept(invitation, newcomer)
      assert organization_user.role == "write"
      assert Organizations.get_role(organization, newcomer) == "write"
    end

    test "joins whichever account is signed in, not the one owning the address", %{
      organization: organization,
      admin: admin
    } do
      other = insert(:user)
      {:ok, invitation} = invite(organization, admin, user_email(other))

      newcomer = insert(:user)
      assert {:ok, _organization_user} = accept(invitation, newcomer)

      assert Organizations.get_role(organization, newcomer) == "read"
      refute Organizations.get_role(organization, other)
    end

    test "spends the invitation so the link cannot be used twice", %{
      organization: organization,
      admin: admin
    } do
      {:ok, invitation} = invite(organization, admin, "newcomer@example.com")
      raw_token = invitation.raw_token

      assert {:ok, _organization_user} = accept(invitation, insert(:user))
      refute OrganizationInvitations.get_pending_by_token(raw_token)
    end

    test "refuses when the organization has no seat left", %{admin: admin} do
      organization = insert(:organization, billing_seats: 1)
      insert(:organization_user, organization: organization, user: admin, role: "admin")
      {:ok, invitation} = invite(organization, admin, "newcomer@example.com")

      assert {:error, :seats_exhausted} = accept(invitation, insert(:user))
      assert OrganizationInvitations.get_pending_by_token(invitation.raw_token)
    end

    test "consumes the invitation without a second seat for an existing member", %{
      organization: organization,
      admin: admin
    } do
      {:ok, invitation} = invite(organization, admin, "newcomer@example.com")
      newcomer = insert(:user)
      insert(:organization_user, organization: organization, user: newcomer, role: "read")

      assert {:ok, :already_member} = accept(invitation, newcomer)
      refute OrganizationInvitations.get_pending_by_token(invitation.raw_token)
      assert Hexpm.Accounts.Seats.used(organization) == 2
    end

    test "refuses an invitation that has been revoked", %{
      organization: organization,
      admin: admin
    } do
      {:ok, invitation} = invite(organization, admin, "newcomer@example.com")

      {:ok, _} =
        OrganizationInvitations.revoke(organization, invitation, audit: audit_data(admin))

      assert {:error, :invitation_unavailable} = accept(invitation, insert(:user))
    end
  end

  describe "revoke/3" do
    test "takes the invitation mail that hasn't gone out with it", %{
      organization: organization,
      admin: admin
    } do
      {:ok, invitation} = invite(organization, admin, "newcomer@example.com")
      assert [_mail] = Repo.all(OutboxEntry.undelivered())

      {:ok, _} =
        OrganizationInvitations.revoke(organization, invitation, audit: audit_data(admin))

      assert Repo.all(OutboxEntry) == []
    end

    test "leaves a mail that was already delivered", %{organization: organization, admin: admin} do
      {:ok, invitation} = invite(organization, admin, "newcomer@example.com")
      Repo.update_all(OutboxEntry, set: [delivered_at: DateTime.utc_now()])

      {:ok, _} =
        OrganizationInvitations.revoke(organization, invitation, audit: audit_data(admin))

      assert [%{delivered_at: %DateTime{}}] = Repo.all(OutboxEntry)
    end
  end

  describe "get_pending_by_token/1" do
    test "does not answer for an expired invitation", %{
      organization: organization,
      admin: admin
    } do
      {:ok, invitation} = invite(organization, admin, "newcomer@example.com")

      invitation
      |> Ecto.Changeset.change(
        expires_at: DateTime.add(DateTime.utc_now(), -1, :second),
        sent_at: DateTime.add(DateTime.utc_now(), -8 * 24 * 60 * 60, :second)
      )
      |> Repo.update!()

      refute OrganizationInvitations.get_pending_by_token(invitation.raw_token)
    end

    test "does not answer for a token that was never issued" do
      refute OrganizationInvitations.get_pending_by_token("nonsense")
      refute OrganizationInvitations.get_pending_by_token(nil)
    end
  end

  describe "all_pending/1" do
    test "leaves out spent, revoked, and expired invitations", %{
      organization: organization,
      admin: admin
    } do
      {:ok, pending} = invite(organization, admin, "pending@example.com")
      {:ok, revoked} = invite(organization, admin, "revoked@example.com")
      {:ok, _} = OrganizationInvitations.revoke(organization, revoked, audit: audit_data(admin))
      {:ok, accepted} = invite(organization, admin, "accepted@example.com")
      {:ok, _} = accept(accepted, insert(:user))

      assert Enum.map(OrganizationInvitations.all_pending(organization), & &1.id) == [pending.id]
    end
  end

  defp invite(organization, admin, email, role \\ "read") do
    OrganizationInvitations.invite(organization, %{"email" => email, "role" => role}, admin,
      audit: audit_data(admin)
    )
  end

  defp invite_user(organization, admin, user, role \\ "read") do
    OrganizationInvitations.invite_user(organization, user, %{"role" => role}, admin,
      audit: audit_data(admin)
    )
  end

  defp decline(invitation, user) do
    invitation = %{
      invitation
      | organization: Repo.preload(invitation, :organization, force: true).organization
    }

    OrganizationInvitations.decline(invitation, user, audit: audit_data(user))
  end

  defp provision(organization, admin, email) do
    OrganizationInvitations.invite(organization, %{"email" => email, "role" => "read"}, nil,
      audit: audit_data(admin)
    )
  end

  defp insert_invitations(organization, invited_by, count, written_at \\ DateTime.utc_now()) do
    rows =
      for index <- 1..count do
        %{
          organization_id: organization.id,
          invited_by_user_id: invited_by && invited_by.id,
          email: "invited#{index}-#{organization.id}@example.com",
          role: "read",
          token_hash: :crypto.strong_rand_bytes(32),
          expires_at: DateTime.add(DateTime.utc_now(), 7 * 24 * 60 * 60),
          inserted_at: written_at,
          updated_at: written_at,
          sent_at: written_at
        }
      end

    Repo.insert_all(Hexpm.Accounts.OrganizationInvitation, rows)
  end

  defp expire(invitation) do
    invitation
    |> Ecto.Changeset.change(
      expires_at: DateTime.add(DateTime.utc_now(), -1, :second),
      sent_at: DateTime.add(DateTime.utc_now(), -8 * 24 * 60 * 60, :second)
    )
    |> Repo.update!()
  end

  defp invite_from_other_organizations(admin, email, count) do
    for _ <- 1..count do
      organization = insert(:organization)
      assert {:ok, _invitation} = invite(organization, admin, email)
    end
  end

  defp user_email(user) do
    Repo.preload(user, :emails).emails |> hd() |> Map.fetch!(:email)
  end

  defp accept(invitation, user) do
    invitation = %{
      invitation
      | organization: Repo.preload(invitation, :organization).organization
    }

    OrganizationInvitations.accept(invitation, user, audit: audit_data(user))
  end
end
