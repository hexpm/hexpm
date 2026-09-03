defmodule Hexpm.Accounts.Organizations do
  use Hexpm.Context

  alias Hexpm.Accounts.OptionalEmails
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
      |> Multi.delete(:organization_user, & &1.member)
      |> Hexpm.Accounts.SSO.remove_member(organization, user)
      |> delete_package_owners(organization, user)
      |> audit(audit_data, "organization.member.remove", {organization, user})

    case Repo.transaction(multi) do
      {:ok, _result} -> :ok
      {:error, :member, :not_member, _} -> :ok
      {:error, :member, :last_member, _} -> {:error, :last_member}
    end
  end

  defp member_to_remove(organization, user) do
    if Seats.used(organization) == 1 do
      {:error, :last_member}
    else
      case Repo.get_by(assoc(organization, :organization_users), user_id: user.id) do
        nil -> {:error, :not_member}
        organization_user -> {:ok, organization_user}
      end
    end
  end

  def change_role(organization, user, params, audit: audit_data) do
    multi =
      Multi.new()
      |> Hexpm.Accounts.SSO.lock_member_removal(organization, user)
      |> Seats.lock(:seats, organization)
      |> Multi.run(:member, fn _repo, _changes -> member_to_change(organization, user) end)
      |> Multi.update(:organization_user, &Organization.change_role(&1.member, params))
      |> audit(audit_data, "organization.member.role", {organization, user, params["role"]})

    case Repo.transaction(multi) do
      {:ok, result} ->
        {:ok, result.organization_user}

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
    if OptionalEmails.allowed?(user, :organization_invite) do
      Emails.organization_invite(organization, user)
      |> Mailer.deliver!()
    end
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
