defmodule Hexpm.Accounts.OrganizationInvitations do
  @moduledoc """
  Invitations to people who do not have an organization membership yet, and may
  not have a Hex account at all.

  The invitation link is the proof: holding it means holding the mailbox it was
  sent to, so whichever account is signed in when the link is followed is the
  account that joins. That is deliberate, because the address an administrator
  knows is usually a work address and the Hex account it belongs to is usually
  older than the job.

  The seat is spent when the invitation is accepted, not when it is sent, so a
  pending invitation costs nothing and an organization cannot be filled up by
  inviting people who never answer.
  """

  use Hexpm.Context

  alias Hexpm.Accounts.OrganizationInvitation

  def all_pending(organization) do
    Repo.all(
      from(invitation in pending_query(organization),
        order_by: [desc: invitation.inserted_at],
        preload: [:invited_by_user]
      )
    )
  end

  def get_pending(organization, id) do
    Repo.one(from(invitation in pending_query(organization), where: invitation.id == ^id))
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
        where: invitation.expires_at > ^DateTime.utc_now(),
        preload: [:organization]
      )
    )
  end

  def get_pending_by_token(_raw_token), do: nil

  def invite(organization, params, invited_by, audit: audit_data) do
    email = OrganizationInvitation.normalize_email(params["email"] || "")
    raw_token = random_token()

    changeset =
      OrganizationInvitation.changeset(%OrganizationInvitation{}, %{
        "organization_id" => organization.id,
        "invited_by_user_id" => invited_by.id,
        "email" => email,
        "role" => params["role"],
        "token_hash" => hash(raw_token),
        "expires_at" => expires_at()
      })

    if member?(organization, email) do
      {:error, :already_member}
    else
      Multi.new()
      |> Multi.insert(:invitation, changeset)
      |> audit(audit_data, "organization.invitation.create", &{organization, &1.invitation})
      |> Repo.transaction()
      |> deliver(organization, raw_token)
    end
  end

  def revoke(organization, invitation, audit: audit_data) do
    Multi.new()
    |> Multi.update(
      :invitation,
      OrganizationInvitation.revoke_changeset(invitation, DateTime.utc_now())
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
  order is invitation, then the organization seat row; nothing else takes both.
  """
  def accept(%OrganizationInvitation{} = invitation, user, audit: audit_data) do
    organization = invitation.organization

    Multi.new()
    |> Multi.run(:invitation, fn _repo, _changes -> locked_pending(invitation) end)
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

      {:error, :seats, reason, _changes} ->
        {:error, reason}

      {:error, :organization_user, changeset, _changes} ->
        {:error, changeset}
    end
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
    |> audit(audit_data, "organization.invitation.accept", {organization, invitation})
  end

  defp deliver({:ok, %{invitation: invitation}}, organization, raw_token) do
    invitation = %{invitation | raw_token: raw_token, organization: organization}

    invitation
    |> Emails.organization_invitation()
    |> Mailer.deliver!()

    {:ok, invitation}
  end

  defp deliver({:error, :invitation, changeset, _changes}, _organization, _raw_token) do
    {:error, changeset}
  end

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
      where: invitation.expires_at > ^DateTime.utc_now()
    )
  end

  defp member?(organization, email) do
    case Users.get(email) do
      nil -> false
      user -> not is_nil(Organizations.get_role(organization, user))
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
