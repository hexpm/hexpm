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

  alias Hexpm.Accounts.{OptionalEmails, OrganizationInvitation, OrganizationInvitationBlock, SCIM}
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
  def all_pending_for_user(user) do
    Repo.all(from(invitation in available_for_user(user), where: is_nil(invitation.declined_at)))
  end

  def all_declined_for_user(user) do
    Repo.all(
      from(invitation in available_for_user(user), where: not is_nil(invitation.declined_at))
    )
  end

  def get_for_user(user, id) do
    Repo.one(from(invitation in available_for_user(user), where: invitation.id == ^id))
  end

  defp available_for_user(%User{id: user_id}) do
    from(invitation in OrganizationInvitation,
      where: invitation.user_id == ^user_id,
      where: is_nil(invitation.accepted_at),
      where: is_nil(invitation.revoked_at),
      where: invitation.expires_at > ^DateTime.utc_now(),
      order_by: [desc: invitation.inserted_at],
      preload: [:organization, :invited_by_user]
    )
  end

  def all_blocks_for_user(%User{id: user_id}) do
    Repo.all(
      from(block in OrganizationInvitationBlock,
        where: block.user_id == ^user_id,
        order_by: [desc: block.inserted_at],
        preload: [:organization]
      )
    )
  end

  def get_block_for_user(%User{id: user_id}, id) do
    Repo.one(
      from(block in OrganizationInvitationBlock,
        where: block.user_id == ^user_id and block.id == ^id,
        preload: [:organization]
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

  @doc """
  Invites an address. When the address belongs to an account that blocked the
  organization, was invited by it in the last day, or has received its daily
  share of invitation mail, the invitation is created without mailing it, so
  the answer never tells the inviter which account owns the address.
  """
  def invite(organization, params, invited_by, audit: audit_data) do
    email = OrganizationInvitation.normalize_email(params["email"] || "")
    recipient = {:email, email}
    account = Users.get(email)

    with_invite_locks(organization, recipient, account, invited_by, fn ->
      issue(organization, recipient, account, invited_by, params["role"], audit_data)
    end)
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
      recipient = {:user, user}

      with_invite_locks(organization, recipient, user, invited_by, fn ->
        issue(organization, recipient, user, invited_by, params["role"], audit_data)
      end)
    else
      {:error, :unverified_primary_email}
    end
  end

  # Refusals the inviter sees only depend on what they named: the account for
  # an invitation by username, the address for one by email. Anything learned
  # by resolving an address to its account only withholds the mail.
  defp issue(organization, recipient, account, invited_by, role, audit_data) do
    cond do
      account && member?(organization, account) ->
        {:error, :already_member}

      refusal = refusal(organization, recipient) ->
        {:error, refusal}

      too_many_invitations?(organization, recipient, invited_by) ->
        {:error, :too_many_invitations}

      true ->
        mail? = not withhold_mail?(organization, recipient, account)

        case lapsed_invitation(organization, recipient) do
          # Expired and declined invitations still occupy the unique recipient
          # slot. Reissuing updates that row and makes the invitation pending.
          %OrganizationInvitation{} = lapsed ->
            reissue(
              organization,
              recipient,
              lapsed,
              invited_by,
              role || lapsed.role,
              mail?,
              audit_data
            )

          nil ->
            insert(organization, recipient, invited_by, role, mail?, audit_data)
        end
    end
  end

  defp refusal(organization, {:user, user}) do
    cond do
      blocked?(organization, user) -> :blocked
      invited_by_username_recently?(organization, user) -> :invitation_cooldown
      true -> nil
    end
  end

  defp refusal(_organization, {:email, _email}), do: nil

  defp withhold_mail?(_organization, {:email, _email}, nil), do: false

  defp withhold_mail?(organization, {:email, _email}, account) do
    blocked?(organization, account) or invited_recently?(organization, account) or
      account_mail_exhausted?(account)
  end

  # A username invitation already passed the cooldown on earlier invitations
  # by username, so only the organization's invitations to the account's
  # addresses are left to count.
  defp withhold_mail?(organization, {:user, user}, user) do
    invited_recently?(organization, user) or account_mail_exhausted?(user)
  end

  defp insert(organization, {:user, user} = recipient, invited_by, role, mail?, audit_data) do
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
    |> deliver(organization, recipient, nil, mail?)
    |> Repo.transaction()
    |> result()
  end

  defp insert(organization, {:email, email} = recipient, invited_by, role, mail?, audit_data) do
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
    |> deliver(organization, recipient, raw_token, mail?)
    |> Repo.transaction()
    |> result()
  end

  defp too_many_invitations?(organization, recipient, invited_by) do
    recipient_count =
      Repo.aggregate(
        from(invitation in recipient_query(recipient),
          where: invitation.sent_at > ago(@recipient_period_seconds, "second")
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
          where: invitation.sent_at > ago(@provisioning_period_seconds, "second")
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
          where: invitation.sent_at > ago(@inviter_period_seconds, "second")
        ),
        :count
      )

    count >= @inviter_limit
  end

  defp blocked?(organization, %User{id: user_id}) do
    Repo.exists?(
      from(block in OrganizationInvitationBlock,
        where: block.organization_id == ^organization.id and block.user_id == ^user_id
      )
    )
  end

  defp invited_by_username_recently?(organization, %User{id: user_id}) do
    Repo.exists?(
      from(invitation in OrganizationInvitation,
        where: invitation.organization_id == ^organization.id,
        where: invitation.user_id == ^user_id,
        where: invitation.sent_at > ago(@recipient_period_seconds, "second")
      )
    )
  end

  defp invited_recently?(organization, account) do
    Repo.exists?(
      from(invitation in account_query(account),
        where: invitation.organization_id == ^organization.id,
        where: invitation.sent_at > ago(@recipient_period_seconds, "second")
      )
    )
  end

  # The same cap as an address gets, over the account's invitations by
  # username and by each of its verified addresses together.
  defp account_mail_exhausted?(account) do
    count =
      Repo.aggregate(
        from(invitation in account_query(account),
          where: invitation.sent_at > ago(@recipient_period_seconds, "second")
        ),
        :count
      )

    count >= @recipient_limit
  end

  defp account_query(%User{id: user_id}) do
    emails =
      from(email in Email,
        where: email.user_id == ^user_id and email.verified,
        select: email.email
      )

    from(invitation in OrganizationInvitation,
      where: invitation.user_id == ^user_id or invitation.email in subquery(emails)
    )
  end

  # Every path that changes an invitation takes the invitation row before the
  # account row, as acceptance does, so they can't deadlock each other. An
  # invitation also locks the inviter, so concurrent invitations from one
  # person can't all pass the inviter's limit. Both accounts are locked in one
  # statement in id order, so two people inviting each other can't deadlock.
  defp with_invite_locks(organization, recipient, account, invited_by, fun) do
    Repo.transaction(fn ->
      Repo.all(from(invitation in slot_query(organization, recipient), lock: "FOR UPDATE"))
      lock_users!(Enum.reject([account, invited_by], &is_nil/1))
      rollback_on_error(fun.())
    end)
  end

  defp with_invitation_lock(invitation, user, fun) do
    Repo.transaction(fn ->
      with {:ok, locked} <- locked_available(invitation) do
        lock_users!([user])
        rollback_on_error(fun.(locked))
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp lock_users!(users) do
    ids = users |> Enum.map(& &1.id) |> Enum.uniq()

    Repo.all(
      from(user in User,
        where: user.id in ^ids,
        order_by: user.id,
        lock: "FOR NO KEY UPDATE",
        select: user.id
      )
    )
  end

  defp rollback_on_error({:ok, result}), do: result
  defp rollback_on_error({:error, reason}), do: Repo.rollback(reason)

  defp lapsed_invitation(organization, recipient) do
    Repo.one(
      from(invitation in slot_query(organization, recipient),
        where: invitation.expires_at <= ^DateTime.utc_now() or not is_nil(invitation.declined_at)
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

  # Reissuing an expired or declined invitation keeps its recipient slot and
  # counts the new mail against the person sending it.
  defp reissue(organization, recipient, invitation, invited_by, role, mail?, audit_data) do
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
    |> deliver(organization, recipient, raw_token, mail?)
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
  Declines an invitation addressed to `user`'s account without changing its expiry.
  """
  def decline(%OrganizationInvitation{user_id: user_id} = invitation, %User{id: user_id} = user,
        audit: audit_data
      )
      when is_integer(user_id) do
    organization = invitation.organization

    with_invitation_lock(invitation, user, fn locked ->
      if OrganizationInvitation.pending?(locked, DateTime.utc_now()) do
        Multi.new()
        |> Multi.update(
          :declined_invitation,
          OrganizationInvitation.decline_changeset(locked, DateTime.utc_now())
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
        end
      else
        {:error, :invitation_unavailable}
      end
    end)
  end

  def decline(%OrganizationInvitation{}, %User{}, audit: _audit_data) do
    {:error, :invitation_unavailable}
  end

  def restore(%OrganizationInvitation{user_id: user_id} = invitation, %User{id: user_id} = user,
        audit: audit_data
      )
      when is_integer(user_id) do
    with_invitation_lock(invitation, user, fn locked ->
      if is_nil(locked.declined_at) or blocked?(invitation.organization, user) do
        {:error, :invitation_unavailable}
      else
        Multi.new()
        |> Multi.update(:invitation, OrganizationInvitation.restore_changeset(locked))
        |> audit(
          audit_data,
          "organization.invitation.restore",
          {invitation.organization, %{locked | user: user}}
        )
        |> Repo.transaction()
        |> case do
          {:ok, %{invitation: invitation}} -> {:ok, invitation}
        end
      end
    end)
  end

  def restore(%OrganizationInvitation{}, %User{}, audit: _audit_data) do
    {:error, :invitation_unavailable}
  end

  def block(%OrganizationInvitation{user_id: user_id} = invitation, %User{id: user_id} = user,
        audit: audit_data
      )
      when is_integer(user_id) do
    with_invitation_lock(invitation, user, fn locked ->
      Multi.new()
      |> Multi.update(
        :invitation,
        OrganizationInvitation.decline_changeset(locked, DateTime.utc_now())
      )
      |> Multi.insert(
        :block,
        %OrganizationInvitationBlock{organization_id: locked.organization_id, user_id: user.id},
        on_conflict: :nothing,
        conflict_target: [:user_id, :organization_id]
      )
      |> Outbox.cancel(:email, group_key: mail_group_key(locked), categories: [@mail_category])
      |> audit(audit_data, "organization.invitation.block", {invitation.organization, user})
      |> Repo.transaction()
      |> case do
        {:ok, %{invitation: invitation}} -> {:ok, invitation}
      end
    end)
  end

  def block(%OrganizationInvitation{}, %User{}, audit: _audit_data) do
    {:error, :invitation_unavailable}
  end

  # A second unblock of the same block finds nothing to delete and answers as
  # an unavailable block, the same as one that never existed.
  def unblock(%OrganizationInvitationBlock{user_id: user_id} = block, %User{id: user_id} = user,
        audit: audit_data
      ) do
    Repo.transaction(fn ->
      lock_users!([user])

      Multi.new()
      |> Multi.delete_all(
        :block,
        from(row in OrganizationInvitationBlock, where: row.id == ^block.id)
      )
      |> Multi.run(:deleted, fn _repo, %{block: {count, _}} ->
        if count == 1, do: {:ok, block}, else: {:error, :invitation_unavailable}
      end)
      |> audit(audit_data, "organization.invitation.unblock", {block.organization, user})
      |> Repo.transaction()
      |> case do
        {:ok, %{deleted: block}} -> block
        {:error, :deleted, reason, _changes} -> Repo.rollback(reason)
      end
    end)
  end

  def unblock(%OrganizationInvitationBlock{}, %User{}, audit: _audit_data) do
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
  defp deliver(multi, organization, {:email, _email}, raw_token, mail?) do
    Multi.run(multi, :email, fn _repo, %{invitation: invitation} ->
      invitation = %{invitation | raw_token: raw_token, organization: organization}

      if mail? do
        invitation
        |> Emails.organization_invitation()
        |> enqueue(invitation)
      end

      {:ok, invitation}
    end)
  end

  # An account that opted out of invitation mail still finds the invitation
  # on its dashboard.
  defp deliver(multi, organization, {:user, user}, nil, mail?) do
    Multi.run(multi, :email, fn _repo, %{invitation: invitation} ->
      invitation = %{invitation | organization: organization, user: user}

      if mail? and OptionalEmails.allowed?(user, :organization_invite) do
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
    with {:ok, locked} <- locked_available(invitation),
         true <- OrganizationInvitation.pending?(locked, DateTime.utc_now()) do
      {:ok, locked}
    else
      _unavailable -> {:error, :invitation_unavailable}
    end
  end

  defp locked_available(invitation) do
    locked =
      Repo.one(
        from(row in OrganizationInvitation, where: row.id == ^invitation.id, lock: "FOR UPDATE")
      )

    if locked && is_nil(locked.accepted_at) && is_nil(locked.revoked_at) &&
         DateTime.compare(locked.expires_at, DateTime.utc_now()) == :gt do
      {:ok, locked}
    else
      {:error, :invitation_unavailable}
    end
  end

  # Declined invitations stay listed, so an administrator can still revoke
  # one the recipient could restore and accept.
  defp pending_query(organization) do
    from(invitation in OrganizationInvitation,
      where: invitation.organization_id == ^organization.id,
      where: is_nil(invitation.accepted_at),
      where: is_nil(invitation.revoked_at),
      where: invitation.expires_at > ^DateTime.utc_now()
    )
  end

  defp member?(organization, user) do
    not is_nil(Organizations.get_role(organization, user))
  end

  defp expires_at do
    DateTime.add(DateTime.utc_now(), OrganizationInvitation.lifetime_seconds(), :second)
  end

  defp random_token do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp hash(value), do: :crypto.hash(:sha256, value)
end
