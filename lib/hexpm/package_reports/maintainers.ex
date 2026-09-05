defmodule Hexpm.PackageReports.Maintainers do
  alias Hexpm.Accounts.{Organization, User}
  alias Hexpm.Repository.Owners
  alias Hexpm.Repo

  def for_package(package) do
    package
    |> package_users()
    |> Enum.flat_map(&expand_user/1)
    |> Enum.map(&identity/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&String.downcase(&1.email))
    |> Enum.sort_by(&String.downcase(&1.email))
  end

  def identity(%User{} = user) do
    case contact(user) do
      %{email: _email} = contact -> contact
      _contact -> nil
    end
  end

  def contact(%User{} = user) do
    contact = %{name: display_name(user), username: user.username}

    case Enum.find(user.emails, &(&1.primary && &1.verified)) do
      nil -> contact
      email -> Map.put(contact, :email, email.email)
    end
  end

  defp package_users(package) do
    owners =
      Owners.all(package,
        user: [:emails, organization: [organization_users: [user: :emails]]]
      )
      |> Enum.map(& &1.user)

    if package.repository_id == 1 do
      owners
    else
      owners ++ organization_members(package.repository.organization_id)
    end
  end

  defp expand_user(%User{organization_id: nil} = user), do: [user]

  defp expand_user(%User{organization: %Organization{} = organization}) do
    organization_members(organization)
  end

  defp expand_user(_user), do: []

  defp organization_members(organization_id) when is_integer(organization_id) do
    Organization
    |> Repo.get!(organization_id)
    |> Repo.preload(organization_users: [user: :emails])
    |> organization_members()
  end

  defp organization_members(%Organization{organization_users: organization_users}) do
    members = Enum.map(organization_users, & &1.user)
    admins = Enum.filter(organization_users, &(&1.role == "admin")) |> Enum.map(& &1.user)

    case Enum.filter(admins, &identity/1) do
      [] -> Enum.filter(members, &identity/1)
      admins -> admins
    end
  end

  defp display_name(%User{full_name: full_name, username: username}) do
    case String.trim(full_name || "") do
      "" -> username
      name -> name
    end
  end
end
