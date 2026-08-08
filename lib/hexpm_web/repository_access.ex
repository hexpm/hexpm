defmodule HexpmWeb.RepositoryAccess do
  @moduledoc """
  Resolves repositories and packages against the repositories the current user
  has access to. Missing and unauthorized resources are indistinguishable.

  An organization the user does belong to but has not authenticated for is the
  exception: they already know they are a member, so it is named along with what
  would let them in.
  """

  alias Hexpm.Accounts.Users
  alias Hexpm.Repository.{Package, Packages}
  alias HexpmWeb.SSOEnforcement

  def fetch_repository(conn_or_socket, repository_name) do
    current_user = conn_or_socket.assigns.current_user
    organizations = Users.all_organizations(current_user)

    case Enum.find(organizations, &(&1.repository.name == repository_name)) do
      nil ->
        :error

      organization ->
        case SSOEnforcement.check(conn_or_socket, organization, current_user) do
          :ok -> {:ok, organization.repository}
          {:error, refusal} -> {:error, refusal, organization}
        end
    end
  end

  def fetch_package(conn_or_socket, repository_name, package_name) do
    case fetch_repository(conn_or_socket, repository_name) do
      {:ok, repository} ->
        case Packages.get(repository, package_name) do
          %Package{} = package -> {:ok, package}
          _ -> :error
        end

      other ->
        other
    end
  end
end
