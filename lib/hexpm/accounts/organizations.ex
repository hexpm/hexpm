defmodule Hexpm.Accounts.Organizations do
  use HexpmWeb, :context

  def all_by_user(user, preload \\ []) do
    Repo.all(assoc(user, :organizations))
    |> Repo.preload(preload)
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

  def access?(organization, user, role) do
    Repo.one!(Organization.access(organization, user, role))
  end

  def create(user, params, audit: audit_data) do
    multi =
      Multi.new()
      |> Multi.insert(:organization, Organization.changeset(%Organization{}, params))
      |> Multi.insert(:repository, fn %{organization: organization} ->
        %Repository{name: organization.name, public: false, organization_id: organization.id}
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
      {:ok, result} -> {:ok, result.organization}
      {:error, :user, changeset, _} -> {:error, changeset}
      {:error, :organization, changeset, _} -> {:error, changeset}
    end
  end

  def add_member(organization, user, params, audit: audit_data) do
    organization_user = %OrganizationUser{organization_id: organization.id, user_id: user.id}

    multi =
      Multi.new()
      |> Multi.insert(:organization_user, Organization.add_member(organization_user, params))
      |> audit(audit_data, "organization.member.add", {organization, user})

    case Repo.transaction(multi) do
      {:ok, result} ->
        send_invite_email(organization, user)
        {:ok, result.organization_user}

      {:error, :organization_user, changeset, _} ->
        {:error, changeset}
    end
  end

  def remove_member(organization, user, audit: audit_data) do
    count = Repo.aggregate(assoc(organization, :organization_users), :count, :id)

    if count == 1 do
      {:error, :last_member}
    else
      organization_user = Repo.get_by(assoc(organization, :organization_users), user_id: user.id)

      if organization_user do
        {:ok, _result} =
          Multi.new()
          |> Multi.delete(:organization_user, organization_user)
          |> audit(audit_data, "organization.member.remove", {organization, user})
          |> Repo.transaction()
      end

      :ok
    end
  end

  def change_role(organization, user, params, audit: audit_data) do
    organization_users = Repo.all(assoc(organization, :organization_users))
    organization_user = Enum.find(organization_users, &(&1.user_id == user.id))
    number_admins = Enum.count(organization_users, &(&1.role == "admin"))

    cond do
      !organization_user ->
        {:error, :unknown_user}

      organization_user.role == "admin" and number_admins == 1 ->
        {:error, :last_admin}

      true ->
        multi =
          Multi.new()
          |> Multi.update(:organization_user, Organization.change_role(organization_user, params))
          |> audit(audit_data, "organization.member.role", {organization, user, params["role"]})

        case Repo.transaction(multi) do
          {:ok, result} ->
            {:ok, result.organization_user}

          {:error, :organization_user, changeset, _} ->
            {:error, changeset}
        end
    end
  end

  def user_count(organization) do
    Repo.aggregate(assoc(organization, :organization_users), :count, :id)
  end

  defp send_invite_email(organization, user) do
    Emails.organization_invite(organization, user)
    |> Mailer.deliver_now_throttled()
  end
end
