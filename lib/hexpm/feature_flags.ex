defmodule Hexpm.FeatureFlags do
  @moduledoc """
  Rollout flags. A flag is `off`, `enabled` for everyone, or in `beta` for the
  users and organizations on its lists.
  """

  import Ecto.Query, only: [from: 2]

  alias Hexpm.Accounts.{Organization, User}
  alias Hexpm.Repo
  alias Hexpm.Repository.{Package, PackageOwner, Repository}

  def mode(flag), do: Keyword.fetch!(config(flag), :mode)

  @doc """
  Whether the flag is on for anyone.
  """
  def available?(flag) do
    case mode(flag) do
      :off -> false
      :beta -> beta_users(flag) != [] or beta_organizations(flag) != []
      :enabled -> true
    end
  end

  @doc """
  Whether the flag is on for a user, organization or package.

  In `beta`, an organization is in when its name is on the organization list.
  A public package is in when one of its owners is on the user or organization
  list, and a private package follows its organization.
  """
  def enabled?(flag, target) do
    case mode(flag) do
      :off -> false
      :beta -> beta?(flag, target)
      :enabled -> true
    end
  end

  defp beta?(flag, %Organization{name: name}), do: name in beta_organizations(flag)

  defp beta?(flag, %User{username: name}), do: name in beta_users(flag)

  # Owners include organizations, whose users have the organization's name.
  defp beta?(flag, %Package{repository_id: 1, id: id}) do
    names = beta_users(flag) ++ beta_organizations(flag)

    from(po in PackageOwner,
      join: u in assoc(po, :user),
      where: po.package_id == ^id and u.username in ^names
    )
    |> Repo.exists?()
  end

  defp beta?(flag, %Package{repository: %Repository{name: name}}),
    do: name in beta_organizations(flag)

  defp beta_users(flag), do: Keyword.get(config(flag), :beta_users, [])
  defp beta_organizations(flag), do: Keyword.get(config(flag), :beta_organizations, [])

  defp config(flag) do
    :hexpm
    |> Application.fetch_env!(:feature_flags)
    |> Keyword.fetch!(flag)
  end
end
