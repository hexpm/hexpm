defmodule Hexpm.Accounts.OrganizationInvitations do
  @moduledoc """
  Invitations to people who do not have an organization membership yet, and may
  not have a Hex account at all.

  The invitation link is the proof: holding it means holding the mailbox it was
  sent to, so whichever account is signed in when the link is followed is the
  account that joins. That is deliberate, because the address an administrator
  knows is usually a work address and the Hex account it belongs to is usually
  older than the job.

  An invitation can instead name an existing account, which is how an
  administrator adds someone by username. Only that account can accept it, and
  it can decline it from its dashboard.

  The seat is spent when the invitation is accepted, not when it is sent, so a
  pending invitation costs nothing and an organization cannot be filled up by
  inviting people who never answer.
  """

  use Hexpm.Context

  alias Hexpm.Accounts.{OptionalEmails, OrganizationInvitation, SCIM}
  alias Hexpm.Emails.Outbox

  # Every invitation mails a recipient the inviter chose, so both the recipient,
  # an address or an account across all organizations, and the inviter are
  # capped. Provisioning has no person behind it, so its invitations are capped
  # per organization, with room for an initial import.
  @recipient_limit 5
  @recipient_period_seconds 24 * 60 * 60
  @inviter_limit 50
  @inviter_period_seconds 60 * 60
  @provisioning_limit 500
  @provisioning_period_seconds 24 * 60 * 60
  @mail_category "organization.invitation"

  def all_pending(organization) do
    Repo.all(
      from(invitation in pending_query(organization),
        order_by: [desc: invitation.inserted_at],
        preload: [:invited_by_user, :user]
      )
    )
  end

  def get_pending(organization, id) do
    Repo.one(
      from(invitation in pending_query(organization),
        where: invitation.id == ^id,
        preload: [:user]
      )
    )
  end

  @doc "The invitations addressed to `user`'s account that it can still answer."
  def all_pending_for_user(%User{id: user_id}) do
    Repo.all(
      from(invitation in OrganizationInvitation,
        where: invitation.user_id == ^user_id,
        where: is_nil(invitation.accepted_at),
        where: is_nil(invitation.revoked_at),
        where: is_nil(invitation.declined_at),
        where: invitation.expires_at > ^DateTime.utc_now(),
        order_by: [desc: invitation.inserted_at],
        preload: [:organization, :invited_by_user]
      )
    )
  end

  def get_pending_for_user(user, id) do
    Enum.find(all_pending_for_user(user), &(&1.id == id))
  end

  @doc """
  Looks an invitation up by the token from the email. Returns nil for a token
  that is unknown, spent, revoked, or expired, so a caller cannot tell those
  apart.
  """
  def get_pending_by_token(raw_token) when is_binary(raw_token) do
    Repo.one(
      from(invitation in OrganizationInvitation,
        where: invitation.token_hash == ^hash(raw_token),
        where: is_nil(invitation.accepted_at),
        where: is_nil(invitation.revoked_at),
        where: is_nil(invitation.declined_at),
        where: invitation.expires_at > ^DateTime.utc_now(),
        preload: [:organization]
      )
    )
  end

  def get_pending_by_token(_raw_token), do: nil

  def get_pending_by_email(organization, email) do
    email = OrganizationInvitation.normalize_email(email)
    Repo.one(from(invitation in pending_query(organization), where: invitation.email == ^email))
  end

  def invite(organization, params, invited_by, audit: audit_data) do
    email = OrganizationInvitation.normalize_email(params["email"] || "")
    issue(organization, {:email, email}, invited_by, params["role"], audit_data)
  end

  @doc """
  Invites an existing account, which joins once it accepts.

  `invited_by` is a person rather than an organization key, so every invitation
  counts against someone's limit no matter how many organizations they run.
  """
  def invite_user(organization, user, params, invited_by, opts)

  def invite_user(_organization, %User{organization_id: id}, _params, _invited_by, _opts)
      when is_integer(id) do
    {:error, :organization_user}
  end

  def invite_user(organization, %User{} = user, params, %User{} = invited_by, audit: audit_data) do
    user = Repo.preload(user, :emails)

    if User.verified_primary_email?(user) do
      issue(organization, {:user, user}, invited_by, params["role"], audit_data)
    else
      {:error, :unverified_primary_email}
    end
  end

  defp issue(organization, recipient, invited_by, role, audit_data) do
    cond do
      member?(organization, recipient) ->
        {:error, :already_member}

      declined?(organization, recipient) ->
        {:error, :declined}

      too_many_invitations?(organization, recipient, invited_by) ->
        {:error, :too_many_invitations}

      lapsed = lapsed_invitation(organization, recipient) ->
        # The unique index that stops two live invitations for one recipient
        # cannot exclude expired rows, because a partial index predicate has to
        # be immutable and expiry is a comparison against now. So an expired
        # invitation still holds the slot, and no read path shows it. Reissuing
        # it is what the administrator meant by inviting the recipient again.
        reissue(organization, recipient, lapsed, invited_by, role || lapsed.role, audit_data)

      true ->
        insert(organization, recipient, invited_by, role, audit_data)
    end
  end

  defp insert(organization, {:user, user} = recipient, invited_by, role, audit_data) do
    changeset =
      OrganizationInvitation.user_changeset(%OrganizationInvitation{}, %{
        "organization_id" => organization.id,
        "invited_by_user_id" => invited_by.id,
        "user_id" => user.id,
        "role" => role,
        "expires_at" => expires_at()
      })

    Multi.new()
    |> Multi.insert(:invitation, changeset)
    |> audit(
      audit_data,
      "organization.invitation.create",
      &{organization, with_recipient(&1.invitation, recipient)}
    )
    |> deliver(organization, recipient, nil)
    |> Repo.transaction()
    |> result()
  end

  defp insert(organization, {:email, email} = recipient, invited_by, role, audit_data) do
    raw_token = random_token()

    changeset =
      OrganizationInvitation.changeset(%OrganizationInvitation{}, %{
        "organization_id" => organization.id,
        # nil when the inviter is not a person, such as SCIM provisioning.
        "invited_by_user_id" => invited_by && invited_by.id,
        "email" => email,
        "role" => role,
        "token_hash" => hash(raw_token),
        "expires_at" => expires_at()
      })

    Multi.new()
    |> Multi.insert(:invitation, changeset)
    |> audit(audit_data, "organization.invitation.create", &{organization, &1.invitation})
    |> deliver(organization, recipient, raw_token)
    |> Repo.transaction()
    |> result()
  end

  # An invitation row is written when it is created and when it is reissued,
  # the two writes that send mail, so its updated_at counts every mail to the
  # recipient. Revoking, declining or accepting writes it too, which only
  # counts toward the limit sooner.
  defp too_many_invitations?(organization, recipient, invited_by) do
    recipient_count =
      Repo.aggregate(
        from(invitation in recipient_query(recipient),
          where: invitation.updated_at > ago(@recipient_period_seconds, "second")
        ),
        :count
      )

    recipient_count >= @recipient_limit or inviter_over_limit?(organization, invited_by)
  end

  defp inviter_over_limit?(organization, nil) do
    count =
      Repo.aggregate(
        from(invitation in OrganizationInvitation,
          where: invitation.organization_id == ^organization.id,
          where: is_nil(invitation.invited_by_user_id),
          where: invitation.updated_at > ago(@provisioning_period_seconds, "second")
        ),
        :count
      )

    count >= @provisioning_limit
  end

  defp inviter_over_limit?(_organization, %User{id: id}) do
    count =
      Repo.aggregate(
        from(invitation in OrganizationInvitation,
          where: invitation.invited_by_user_id == ^id,
          where: invitation.inserted_at > ago(@inviter_period_seconds, "second")
        ),
        :count
      )

    count >= @inviter_limit
  end

  # A declined invitation keeps its slot until the hold ends, and inviting the
  # recipient before then is refused rather than reissued.
  defp declined?(organization, recipient) do
    Repo.exists?(
      from(invitation in slot_query(organization, recipient),
        where: not is_nil(invitation.declined_at),
        where: invitation.expires_at > ^DateTime.utc_now()
      )
    )
  end

  defp lapsed_invitation(organization, recipient) do
    Repo.one(
      from(invitation in slot_query(organization, recipient),
        where: invitation.expires_at <= ^DateTime.utc_now()
      )
    )
  end

  # The row holding the organization's one slot for the recipient, whatever
  # state it is in, mirroring the predicate of the unique pending indexes.
  defp slot_query(organization, recipient) do
    from(invitation in recipient_query(recipient),
      where: invitation.organization_id == ^organization.id,
      where: is_nil(invitation.accepted_at),
      where: is_nil(invitation.revoked_at)
    )
  end

  defp recipient_query({:email, email}),
    do: from(invitation in OrganizationInvitation, where: invitation.email == ^email)

  defp recipient_query({:user, %User{id: user_id}}),
    do: from(invitation in OrganizationInvitation, where: invitation.user_id == ^user_id)

  # An expired invitation still holds the one-per-recipient slot, so inviting
  # that recipient again reissues the row rather than being refused. The row
  # takes the new inviter, so the mail counts against whoever sent it.
  defp reissue(organization, recipient, invitation, invited_by, role, audit_data) do
    raw_token = recipient_token(recipient)

    Multi.new()
    |> Multi.update(
      :invitation,
      OrganizationInvitation.reissue_changeset(
        invitation,
        invited_by,
        role,
        raw_token && hash(raw_token),
        expires_at()
      )
    )
    |> audit(
      audit_data,
      "organization.invitation.create",
      &{organization, with_recipient(&1.invitation, recipient)}
    )
    |> deliver(organization, recipient, raw_token)
    |> Repo.transaction()
    |> result()
  end

  defp with_recipient(invitation, {:user, user}), do: %{invitation | user: user}
  defp with_recipient(invitation, {:email, _email}), do: invitation

  defp recipient_token({:email, _email}), do: random_token()
  defp recipient_token({:user, _user}), do: nil

  # The mail is cancelled with the invitation, because a revoke can land before
  # the outbox delivers it, as when provisioning renames or deactivates someone
  # in the request that invited them. Mail already handed to the provider stays
  # sent.
  def revoke(organization, invitation, audit: audit_data) do
    Multi.new()
    |> Multi.update(
      :invitation,
      OrganizationInvitation.revoke_changeset(invitation, DateTime.utc_now())
    )
    |> Outbox.cancel(:email,
      group_key: mail_group_key(invitation),
      categories: [@mail_category]
    )
    |> audit(audit_data, "organization.invitation.revoke", &{organization, &1.invitation})
    |> Repo.transaction()
    |> case do
      {:ok, %{invitation: invitation}} -> {:ok, invitation}
      {:error, :invitation, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Joins `user` to the organization the invitation names.

  The invitation row is locked before the seat is claimed, so two people
  following the same link at once produce one membership and one refusal. Lock
  order is the organization's SSO connection when it has one, then the
  invitation, then the organization seat row; provisioning writes take the
  same three in the same order.
  """
  def accept(invitation, user, opts)

  def accept(%OrganizationInvitation{user_id: invitee_id}, %User{id: user_id}, _opts)
      when is_integer(invitee_id) and invitee_id != user_id do
    {:error, :invitation_unavailable}
  end

  def accept(%OrganizationInvitation{} = invitation, user, audit: audit_data) do
    organization = invitation.organization

    Multi.new()
    |> SCIM.lock_provisioning(organization)
    |> Multi.run(:invitation, fn _repo, _changes -> locked_pending(invitation) end)
    |> Hexpm.Accounts.OrganizationTFA.admit(organization, user)
    |> Multi.run(:existing_role, fn _repo, _changes ->
      {:ok, Organizations.get_role(organization, user)}
    end)
    |> Multi.merge(fn %{invitation: invitation, existing_role: existing_role} ->
      join(organization, user, invitation, existing_role, audit_data)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{organization_user: organization_user}} ->
        {:ok, organization_user}

      {:ok, %{existing_role: role}} when is_binary(role) ->
        {:ok, :already_member}

      {:error, :invitation, reason, _changes} ->
        {:error, reason}

      {:error, :tfa_admission, reason, _changes} ->
        {:error, reason}

      {:error, :seats, reason, _changes} ->
        {:error, reason}

      {:error, :organization_user, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  Declines an invitation addressed to `user`'s account. The organization can't
  invite the account again until the hold on the declined invitation ends.
  """
  def decline(%OrganizationInvitation{user_id: user_id} = invitation, %User{id: user_id} = user,
        audit: audit_data
      )
      when is_integer(user_id) do
    organization = invitation.organization

    Multi.new()
    |> Multi.run(:invitation, fn _repo, _changes -> locked_pending(invitation) end)
    |> Multi.update(
      :declined_invitation,
      &OrganizationInvitation.decline_changeset(&1.invitation, DateTime.utc_now())
    )
    |> Outbox.cancel(:email,
      group_key: mail_group_key(invitation),
      categories: [@mail_category]
    )
    |> audit(
      audit_data,
      "organization.invitation.decline",
      {organization, %{invitation | user: user}}
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{declined_invitation: invitation}} -> {:ok, invitation}
      {:error, :invitation, reason, _changes} -> {:error, reason}
    end
  end

  def decline(%OrganizationInvitation{}, %User{}, audit: _audit_data) do
    {:error, :invitation_unavailable}
  end

  # Someone who is already a member consumes the invitation without spending a
  # second seat, so an administrator who invited and then added the same person
  # does not leave a link that stays live.
  defp join(organization, user, invitation, existing_role, audit_data)
       when is_binary(existing_role) do
    consume(Multi.new(), organization, user, invitation, audit_data)
  end

  defp join(organization, user, invitation, nil, audit_data) do
    Multi.new()
    |> Seats.claim(:seats, organization)
    |> Multi.insert(:organization_user, fn _changes ->
      organization_user = %OrganizationUser{organization_id: organization.id, user_id: user.id}
      Organization.add_member(organization_user, %{"role" => invitation.role})
    end)
    |> audit(audit_data, "organization.member.add", {organization, user})
    |> consume(organization, user, invitation, audit_data)
  end

  defp consume(multi, organization, user, invitation, audit_data) do
    multi
    |> Multi.update(
      :accepted_invitation,
      OrganizationInvitation.accept_changeset(invitation, user, DateTime.utc_now())
    )
    |> Multi.run(:scim_handle, fn _repo, _changes -> SCIM.adopt_acceptance(invitation, user) end)
    |> audit(audit_data, "organization.invitation.accept", {organization, invitation})
  end

  # Queued in the same transaction as the invitation. Delivering afterwards
  # meant a mail failure answered the caller with the invitation already
  # committed, and the retry adopted that invitation without mailing anyone.
  defp deliver(multi, organization, {:email, _email}, raw_token) do
    Multi.run(multi, :email, fn _repo, %{invitation: invitation} ->
      invitation = %{invitation | raw_token: raw_token, organization: organization}

      invitation
      |> Emails.organization_invitation()
      |> enqueue(invitation)

      {:ok, invitation}
    end)
  end

  # An account that opted out of invitation mail still finds the invitation
  # on its dashboard.
  defp deliver(multi, organization, {:user, user}, nil) do
    Multi.run(multi, :email, fn _repo, %{invitation: invitation} ->
      invitation = %{invitation | organization: organization, user: user}

      if OptionalEmails.allowed?(user, :organization_invite) do
        invitation
        |> Emails.organization_user_invitation()
        |> enqueue(invitation)
      end

      {:ok, invitation}
    end)
  end

  defp enqueue(email, invitation) do
    Outbox.enqueue!(email,
      category: @mail_category,
      group_key: mail_group_key(invitation),
      scope_key: "organization:#{invitation.organization_id}"
    )
  end

  defp mail_group_key(invitation), do: "organization-invitation:#{invitation.id}"

  defp result({:ok, %{email: invitation}}), do: {:ok, invitation}
  defp result({:error, :invitation, changeset, _changes}), do: {:error, changeset}

  defp locked_pending(invitation) do
    locked =
      Repo.one(
        from(row in OrganizationInvitation, where: row.id == ^invitation.id, lock: "FOR UPDATE")
      )

    if locked && OrganizationInvitation.pending?(locked, DateTime.utc_now()) do
      {:ok, locked}
    else
      {:error, :invitation_unavailable}
    end
  end

  defp pending_query(organization) do
    from(invitation in OrganizationInvitation,
      where: invitation.organization_id == ^organization.id,
      where: is_nil(invitation.accepted_at),
      where: is_nil(invitation.revoked_at),
      where: is_nil(invitation.declined_at),
      where: invitation.expires_at > ^DateTime.utc_now()
    )
  end

  defp member?(organization, {:user, user}) do
    not is_nil(Organizations.get_role(organization, user))
  end

  defp member?(organization, {:email, email}) do
    case Users.get(email) do
      nil -> false
      user -> member?(organization, {:user, user})
    end
  end

  defp expires_at do
    DateTime.add(DateTime.utc_now(), OrganizationInvitation.lifetime_seconds(), :second)
  end

  defp random_token do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp hash(value), do: :crypto.hash(:sha256, value)
end
