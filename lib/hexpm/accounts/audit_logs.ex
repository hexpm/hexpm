defmodule Hexpm.Accounts.AuditLogs do
  use Hexpm.Context

  def all_by(schema) do
    AuditLog.all_by(schema)
    |> AuditLog.newest_first()
    |> Repo.all()
  end

  def all_by(schema, page, per_page) do
    AuditLog.all_by(schema)
    |> AuditLog.newest_first()
    |> Hexpm.Utils.paginate(page, per_page)
    |> Repo.all()
  end

  @doc """
  Return the number of audit_logs belong to the schema (user/organization/package)
  """
  def count_by(schema) do
    AuditLog.count_by(schema)
    |> Repo.one()
  end

  @doc """
  Return a map of policy name -> audit_log count for every policy in the
  organization, in a single grouped query.
  """
  def count_by_policies(organization) do
    AuditLog.count_by_policies(organization)
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Removes a deleted account's email addresses from the audit log entries it
  made, keeping its id and username as the record of who acted. Runs in the
  transaction that deletes the user, before the delete nulls the entries'
  `user_id`.

  Entries about an organization's email addresses keep them: those addresses
  belong to the organization's own record. The invitations it accepted lose
  the address they were sent to.
  """
  def scrub_user(multi, %User{id: user_id}) do
    entries = from(a in AuditLog, where: a.user_id == ^user_id)

    multi
    |> Multi.update_all(
      :scrub_audit_user_data,
      from(a in entries,
        where: not is_nil(a.user_data),
        update: [
          set: [
            user_data:
              fragment(
                "jsonb_build_object('id', ?->'id', 'username', ?->'username')",
                a.user_data,
                a.user_data
              )
          ]
        ]
      ),
      []
    )
    |> Multi.update_all(
      :scrub_audit_emails,
      from(a in entries,
        where: like(a.action, "email.%"),
        where: not fragment("jsonb_exists(?, 'organization')", a.params),
        update: [
          set: [
            params:
              fragment(
                "? - 'email' #- '{old_email,email}' #- '{new_email,email}'",
                a.params
              )
          ]
        ]
      ),
      []
    )
    |> Multi.update_all(
      :scrub_audit_provider_emails,
      from(a in entries,
        where: like(a.action, "user_provider.%"),
        update: [set: [params: fragment("? - 'provider_email'", a.params)]]
      ),
      []
    )
    |> Multi.update_all(
      :scrub_audit_invitation_emails,
      from(a in entries,
        where: a.action == "organization.invitation.accept",
        update: [set: [params: fragment("? #- '{invitation,email}'", a.params)]]
      ),
      []
    )
  end

  def admin() do
    %{
      user: Hexpm.Accounts.Users.get("admin"),
      auth_credential: nil,
      user_agent: "ADMIN",
      remote_ip: nil
    }
  end

  @doc """
  Audit data for something a background job did to an organization, with the
  organization as the subject because no person acted.
  """
  def system(organization) do
    %{user: organization, auth_credential: nil, user_agent: "SYSTEM", remote_ip: nil}
  end

  @doc """
  Audit data for a write the identity provider's provisioning agent made. The
  organization is the subject, as it is for `system/1`, but the agent's address
  is recorded: these rows are what an administrator reads to tell a
  provisioning change from one a person made.
  """
  def scim(organization, remote_ip) do
    %{user: organization, auth_credential: nil, user_agent: "SCIM", remote_ip: remote_ip}
  end
end
