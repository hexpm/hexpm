defmodule Hexpm.Accounts.Organizations do
  use HexpmWeb, :context

  def all_public() do
    Repo.all(from(r in Organization, where: r.public))
  end

  def all_by_user(user) do
    Repo.all(assoc(user, :organizations))
  end

  def get(name, preload \\ []) do
    Repo.get_by(Organization, name: name)
    |> Repo.preload(preload)
  end

  def access?(%Organization{public: false}, nil, _role) do
    false
  end

  def access?(%Organization{public: false} = organization, user, role) do
    Repo.one!(Organization.has_access(organization, user, role))
  end

  def create(user, params, audit: audit_data) do
    multi =
      Multi.new()
      |> Multi.insert(:organization, Organization.changeset(%Organization{}, params))
      |> Multi.insert(:organization_user, fn %{organization: organization} ->
        organization_user = %OrganizationUser{
          organization_id: organization.id,
          user_id: user.id,
          role: "admin"
        }

        Organization.add_member(organization_user, %{})
      end)
      |> audit(audit_data, "organization.create", fn %{organization: organization} ->
        organization
      end)

    case Repo.transaction(multi) do
      {:ok, result} ->
        {:ok, result.organization}

      {:error, :organization, changeset, _} ->
        {:error, changeset}
    end
  end

  def add_member(organization, username, params, audit: audit_data) do
    if user = Users.get(username, [:emails]) do
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
    else
      {:error, :unknown_user}
    end
  end

  def remove_member(organization, username, audit: audit_data) do
    if user = Users.get(username) do
      count = Repo.aggregate(assoc(organization, :organization_users), :count, :id)

      if count == 1 do
        {:error, :last_member}
      else
        organization_user =
          Repo.get_by(assoc(organization, :organization_users), user_id: user.id)

        if organization_user do
          {:ok, _result} =
            Multi.new()
            |> Multi.delete(:organization_user, organization_user)
            |> audit(audit_data, "organization.member.remove", {organization, user})
            |> Repo.transaction()
        end

        :ok
      end
    else
      {:error, :unknown_user}
    end
  end

  def change_role(organization, username, params, audit: audit_data) do
    user = Users.get(username)
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

  def members_count(organization) do
    Repo.aggregate(assoc(organization, :organization_users), :count, :id)
  end

  defp send_invite_email(organization, user) do
    Emails.organization_invite(organization, user)
    |> Mailer.deliver_now_throttled()
  end
end
