defmodule Hexpm.Accounts.OrganizationInvitationsTest do
  use Hexpm.DataCase, async: true
  import Swoosh.TestAssertions

  alias Hexpm.Accounts.{AuditLogs, OrganizationInvitations, Organizations}

  setup do
    organization = insert(:organization, billing_seats: 3)
    admin = insert(:user)
    insert(:organization_user, organization: organization, user: admin, role: "admin")

    %{organization: organization, admin: admin}
  end

  describe "invite/4" do
    test "sends a link the recipient can use", %{organization: organization, admin: admin} do
      assert {:ok, invitation} = invite(organization, admin, "newcomer@example.com")

      assert invitation.email == "newcomer@example.com"
      assert invitation.role == "read"
      assert invitation.invited_by_user_id == admin.id
      assert_email_sent(fn email -> email.to == [{"", "newcomer@example.com"}] end)

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

    test "rejects an address that is not one", %{organization: organization, admin: admin} do
      assert {:error, changeset} = invite(organization, admin, "not-an-address")
      assert errors_on(changeset).email == "is not a valid email"
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

  describe "accept/3" do
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

  describe "get_pending_by_token/1" do
    test "does not answer for an expired invitation", %{
      organization: organization,
      admin: admin
    } do
      {:ok, invitation} = invite(organization, admin, "newcomer@example.com")

      invitation
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1, :second))
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
