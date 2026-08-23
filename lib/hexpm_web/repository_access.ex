defmodule HexpmWeb.RepositoryAccess do
  @moduledoc """
  Resolves repositories and packages against the repositories the current user
  has access to. Missing and unauthorized resources are indistinguishable.

  An organization the user does belong to but has not authenticated for is the
  exception: they already know they are a member, so it is named along with what
  would let them in. That is the only refusal these surfaces see, because a
  browser carries no credential for the personal-key branch of enforcement to
  look at.
  """

  alias Hexpm.Accounts.Users
  alias Hexpm.Repository.{Package, Packages}
  alias HexpmWeb.SSOEnforcement

  @doc """
  The repository behind this name, if the current user reaches it.

  `reload: true` resolves the memberships from the database instead of from the
  association the caller loaded. A connected LiveView loads them once, at mount,
  and a member removed since is refused by nothing else: enforcement only
  governs members.
  """
  def fetch_repository(conn_or_socket, repository_name, opts \\ []) do
    current_user = conn_or_socket.assigns.current_user
    organizations = organizations(current_user, opts)

    case Enum.find(organizations, &(&1.repository.name == repository_name)) do
      nil ->
        :error

      organization ->
        case SSOEnforcement.check(conn_or_socket, organization, current_user) do
          :ok -> {:ok, %{organization.repository | organization: organization}}
          {:error, :sso_required} -> {:error, :sso_required, organization}
        end
    end
  end

  def fetch_package(conn_or_socket, repository_name, package_name, opts \\ []) do
    case fetch_repository(conn_or_socket, repository_name, opts) do
      {:ok, repository} ->
        case Packages.get(repository, package_name) do
          %Package{} = package -> {:ok, package}
          _ -> :error
        end

      other ->
        other
    end
  end

  defp organizations(current_user, opts) do
    if Keyword.get(opts, :reload, false) do
      Users.reload_organizations(current_user)
    else
      Users.all_organizations(current_user)
    end
  end
end
