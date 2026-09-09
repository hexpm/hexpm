defmodule Hexpm.Accounts.Organizations do
  use Hexpm.Context

  alias Hexpm.Accounts.OptionalEmails
  alias Hexpm.Emails.Outbox
  alias Hexpm.Repository.OrgNamesPublisher

  def all_by_user(user, preload \\ []) do
    from(organization in assoc(user, :organizations), order_by: organization.name)
    |> Repo.all()
    |> Repo.preload(preload)
  end

  def all_members(organization, preload \\ []) do
    from(organization_user in assoc(organization, :organization_users),
      join: user in assoc(organization_user, :user),
      order_by: user.username
    )
    |> Repo.all()
    |> Repo.preload(preload)
  end

  def all_admin_notifiable_emails(opts \\ []) do
    Organization.all_admin_notifiable_emails(opts)
    |> Repo.all()
  end

  def get(name, preload \\ []) do
    Repo.get_by(Organization, name: name)
    |> Repo.preload(preload)
  end

  def get_role(organization, user) do
    org_user = Repo.get_by(OrganizationUser, organization_id: organization.id, user_id: user.id)
    org_user && org_user.role
  end

  def preload(organization, preload) do
    Repo.preload(organization, preload)
  end

  def access?(_organization, nil = _user, _role) do
    false
  end

  def access?(%Organization{id: id}, %Organization{id: id}, _role) do
    true
  end

  def access?(organization, user, role) do
    Repo.one!(Organization.access(organization, user, role))
  end

  def create(user, params, audit: audit_data) do
    multi =
      Multi.new()
      |> Multi.insert(:organization, Organization.changeset(%Organization{}, params))
      |> Multi.insert(:repository, fn %{organization: organization} ->
        %Repository{name: organization.name, organization_id: organization.id}
      end)
      |> Multi.insert(:user, &User.build_organization(&1.organization))
      |> Multi.insert(:organization_user, fn %{organization: organization} ->
        organization_user = %OrganizationUser{
          organization_id: organization.id,
          user_id: user.id,
          role: "admin"
        }

        Organization.add_member(organization_user, %{})
      end)
      |> audit(audit_data, "organization.create", & &1.organization)

    case Repo.transaction(multi) do
      {:ok, result} ->
        publish_org_names()
        {:ok, result.organization}

      {:error, :user, changeset, _} ->
        {:error, changeset}

      {:error, :organization, changeset, _} ->
        {:error, changeset}
    end
  end

  def create_from_user(organization_user, admin_user) do
    multi =
      Multi.new()
      |> Multi.insert(:organization, Organization.build_from_user(organization_user))
      |> Multi.insert(:repository, fn %{organization: organization} ->
        %Repository{name: organization.name, organization_id: organization.id}
      end)
      |> Multi.update(:user, &User.to_organization(organization_user, &1.organization))
      |> Multi.insert(:organization_user, fn %{organization: organization} ->
        organization_user = %OrganizationUser{
          organization_id: organization.id,
          user_id: admin_user.id,
          role: "admin"
        }

        Organization.add_member(organization_user, %{})
      end)

    case Repo.transaction(multi) do
      {:ok, _result} = ok ->
        publish_org_names()
        ok

      {:error, _, _, _} = error ->
        error
    end
  end

  @doc """
  Deletes the organization and everything scoped to it: its repository with
  every package and release in it, its members, keys, audit logs and the user
  row carrying its name. The name is reserved afterwards so nobody can take it
  again, as an organization or as a username.

  Objects in the repository, preview and docs buckets are left where they are
  and the billing subscription is left running; `Hexpm.AdminTasks.delete_organization/2`
  handles both.
  """
  def delete(%Organization{id: 1}, audit: _audit_data) do
    {:error, :public_organization}
  end

  def delete(organization, audit: audit_data) do
    organization = Repo.preload(organization, [:repository, :user])

    multi =
      Multi.new()
      |> Multi.delete_all(
        :audit_logs,
        from(a in AuditLog, where: a.organization_id == ^organization.id)
      )
      |> Multi.delete_all(:keys, from(k in Key, where: k.organization_id == ^organization.id))
      |> Multi.delete_all(:organization_users, assoc(organization, :organization_users))
      |> delete_repository(organization.repository)
      |> delete_organization_user(organization.user)
      |> Multi.insert(:reserved_name, %ReservedUsername{name: organization.name},
        on_conflict: :nothing
      )
      |> audit(audit_data, "organization.delete", organization)
      |> Multi.delete(:organization, organization)

    case Repo.transaction(multi) do
      {:ok, _result} ->
        publish_org_names()
        :ok

      {:error, _operation, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp delete_repository(multi, nil), do: multi

  # Releases and package reports go before packages because neither
  # releases_package_id_fkey nor package_reports_package_id_fkey cascades, and
  # reserved_packages before the repository for the same reason.
  defp delete_repository(multi, repository) do
    packages = from(p in Package, where: p.repository_id == ^repository.id)
    package_ids = from(p in packages, select: p.id)

    multi
    |> Multi.delete_all(
      :package_reports,
      from(r in Hexpm.PackageReports.Report, where: r.package_id in subquery(package_ids))
    )
    |> Multi.delete_all(
      :releases,
      from(r in Release, where: r.package_id in subquery(package_ids))
    )
    |> Multi.delete_all(:packages, packages)
    |> Multi.delete_all(
      :reserved_packages,
      from(r in "reserved_packages", where: r.repository_id == ^repository.id)
    )
    |> Multi.delete(:repository, repository)
  end

  defp delete_organization_user(multi, nil), do: multi

  # An organization made out of an existing account keeps that account's keys
  # and tokens. Audit logs reference both with ON DELETE SET NULL, and letting
  # the user's deletion cascade into them instead hits the foreign key trigger
  # ordering that fails the transaction, which is what Users.delete/2 takes
  # them out in their own statements to avoid.
  defp delete_organization_user(multi, user) do
    multi
    |> Multi.delete_all(:user_keys, assoc(user, :keys))
    |> Multi.delete_all(
      :user_oauth_tokens,
      from(t in Hexpm.OAuth.Token, where: t.user_id == ^user.id)
    )
    |> Multi.delete(:user, user)
  end

  def merge_with_user(
        %Organization{name: name} = organization,
        %User{username: name, organization_id: nil} = user
      ) do
    Repo.update(User.to_organization(user, organization))
  end

  def add_member(_organization, %User{organization_id: id}, _params, _opts) when is_integer(id) do
    {:error, :organization_user}
  end

  def add_member(organization, %User{organization_id: nil} = user, params, audit: audit_data) do
    if User.verified_primary_email?(user) do
      insert_member(organization, user, params, audit_data)
    else
      {:error, :unverified_primary_email}
    end
  end

  defp insert_member(organization, user, params, audit_data) do
    multi =
      Multi.new()
      |> Hexpm.Accounts.OrganizationTFA.admit(organization, user)
      |> Seats.claim(:seats, organization)
      |> Multi.insert(:organization_user, fn _changes ->
        organization_user = %OrganizationUser{organization_id: organization.id, user_id: user.id}
        Organization.add_member(organization_user, params)
      end)
      |> audit(audit_data, "organization.member.add", {organization, user})

    case Repo.transaction(multi) do
      {:ok, result} ->
        send_invite_email(organization, user)
        {:ok, result.organization_user}

      {:error, :tfa_admission, reason, _} ->
        {:error, reason}

      {:error, :seats, reason, _} ->
        {:error, reason}

      {:error, :organization_user, changeset, _} ->
        {:error, changeset}
    end
  end

  def remove_member(_organization, nil = _user, audit: _audit_data) do
    :ok
  end

  def remove_member(organization, user, audit: audit_data) do
    multi =
      Multi.new()
      |> Hexpm.Accounts.SSO.lock_member_removal(organization, user)
      |> Seats.lock(:seats, organization)
      |> Multi.run(:member, fn _repo, _changes -> member_to_remove(organization, user) end)
      |> Hexpm.Accounts.OrganizationTFA.protect_admin(organization, user)
      |> Multi.delete(:organization_user, & &1.member)
      |> Multi.run(:tfa_notifications, fn _repo, _ ->
        {:ok, Hexpm.Accounts.OrganizationTFANotifications.cancel_member!(organization, user)}
      end)
      |> Hexpm.Accounts.SSO.remove_member(organization, user)
      |> delete_package_owners(organization, user)
      |> audit(audit_data, "organization.member.remove", {organization, user})

    case Repo.transaction(multi) do
      {:ok, _result} -> :ok
      {:error, :member, :not_member, _} -> :ok
      {:error, :member, :last_member, _} -> {:error, :last_member}
      {:error, :eligible_admin, reason, _} -> {:error, reason}
    end
  end

  # Membership before the last-member guard: someone who is not a member cannot
  # be the last one, and removing them is a no-op rather than a refusal.
  defp member_to_remove(organization, user) do
    case Repo.get_by(assoc(organization, :organization_users), user_id: user.id) do
      nil ->
        {:error, :not_member}

      organization_user ->
        if Seats.used(organization) == 1 do
          {:error, :last_member}
        else
          {:ok, organization_user}
        end
    end
  end

  def change_role(organization, user, params, audit: audit_data) do
    multi =
      Multi.new()
      |> Hexpm.Accounts.SSO.lock_member_removal(organization, user)
      |> Seats.lock(:seats, organization)
      |> Hexpm.Accounts.OrganizationTFA.protect_admin(organization, user, params["role"])
      |> Multi.run(:member, fn _repo, _changes -> member_to_change(organization, user) end)
      |> Multi.update(:organization_user, &Organization.change_role(&1.member, params))
      |> audit(audit_data, "organization.member.role", {organization, user, params["role"]})

    case Repo.transaction(multi) do
      {:ok, result} ->
        {:ok, result.organization_user}

      {:error, :eligible_admin, reason, _} ->
        {:error, reason}

      {:error, :member, reason, _} ->
        {:error, reason}

      {:error, :organization_user, changeset, _} ->
        {:error, changeset}
    end
  end

  defp member_to_change(organization, user) do
    organization_users = Repo.all(assoc(organization, :organization_users))
    organization_user = Enum.find(organization_users, &(&1.user_id == user.id))
    number_admins = Enum.count(organization_users, &(&1.role == "admin"))

    cond do
      !organization_user -> {:error, :unknown_user}
      organization_user.role == "admin" and number_admins == 1 -> {:error, :last_admin}
      true -> {:ok, organization_user}
    end
  end

  defp delete_package_owners(multi, organization, user) do
    Multi.delete_all(multi, :package_owners, fn _changes ->
      from(
        po in PackageOwner,
        join: p in assoc(po, :package),
        join: r in assoc(p, :repository),
        where: r.organization_id == ^organization.id,
        where: po.user_id == ^user.id
      )
    end)
  end

  defp send_invite_email(organization, user) do
    send_member_added_email(organization, user)
  end

  @doc """
  Tells someone they were added to an organization. Every path that creates a
  membership without the person asking for it sends this, including
  provisioning. Queued rather than delivered, so a caller can send it inside
  the transaction that creates the membership.
  """
  def send_member_added_email(organization, user) do
    if OptionalEmails.allowed?(user, :organization_invite) do
      Emails.organization_invite(organization, user)
      |> Outbox.enqueue!(
        category: "organization.member_added",
        group_key: "organization-member-added:#{organization.id}:#{user.id}",
        scope_key: "organization:#{organization.id}"
      )
    end

    :ok
  end

  defp publish_org_names do
    OrgNamesPublisher.publish()
  rescue
    error ->
      require Logger
      Logger.error("Failed to publish org_names.csv: #{Exception.message(error)}")
      :ok
  end
end
