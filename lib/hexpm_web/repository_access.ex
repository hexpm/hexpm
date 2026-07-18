defmodule HexpmWeb.RepositoryAccess do
  @moduledoc """
  Resolves repositories and packages against the repositories the given user
  has access to. Missing and unauthorized resources are indistinguishable.
  """

  alias Hexpm.Accounts.Users
  alias Hexpm.Repository.{Package, Packages}

  def fetch_repository(current_user, repository_name) do
    organizations = Users.all_organizations(current_user)

    case Enum.find(organizations, &(&1.repository.name == repository_name)) do
      nil -> :error
      organization -> {:ok, organization.repository}
    end
  end

  def fetch_package(current_user, repository_name, package_name) do
    with {:ok, repository} <- fetch_repository(current_user, repository_name),
         %Package{} = package <- Packages.get(repository, package_name) do
      {:ok, package}
    else
      _ -> :error
    end
  end
end
