defmodule HexpmWeb.PackageOwnerController do
  use HexpmWeb, :controller

  alias HexpmWeb.{PackageLayoutAssigns, ViewHelpers}

  plug :requires_login
  plug :fetch_package
  plug :requires_full_owner
  plug HexpmWeb.Plugs.Sudo

  def index(conn, _params) do
    package = conn.assigns.package

    render(
      conn,
      "index.html",
      [
        title: "Manage owners – #{package.name}",
        container: "container"
      ] ++ PackageLayoutAssigns.for_package(conn, package)
    )
  end

  def create(conn, %{"username" => username} = params) do
    package = conn.assigns.package
    user = Users.get_by_username(username, [:emails, :organization])

    if is_nil(user) do
      conn
      |> put_flash(:error, "User \"#{username}\" not found.")
      |> redirect(to: ViewHelpers.path_for_owners(package))
    else
      case Owners.add(package, user, params, audit: audit_data(conn)) do
        {:ok, _} ->
          conn
          |> put_flash(:info, "#{username} added as owner.")
          |> redirect(to: ViewHelpers.path_for_owners(package))

        {:error, :not_member} ->
          conn
          |> put_flash(:error, "#{username} is not a member of this repository.")
          |> redirect(to: ViewHelpers.path_for_owners(package))

        {:error, :not_organization_transfer} ->
          conn
          |> put_flash(:error, "#{username} is an organization — use a transfer to add it.")
          |> redirect(to: ViewHelpers.path_for_owners(package))

        {:error, :organization_level} ->
          conn
          |> put_flash(:error, "Organizations must be added as full owners.")
          |> redirect(to: ViewHelpers.path_for_owners(package))

        {:error, :organization_user_conflict} ->
          conn
          |> put_flash(:error, "#{username} conflicts with an existing organization owner.")
          |> redirect(to: ViewHelpers.path_for_owners(package))

        {:error, :last_full_owner} ->
          conn
          |> put_flash(:error, "Cannot demote the last full owner of a package.")
          |> redirect(to: ViewHelpers.path_for_owners(package))

        {:error, changeset} ->
          conn
          |> put_flash(:error, changeset_error_to_string(changeset))
          |> redirect(to: ViewHelpers.path_for_owners(package))
      end
    end
  end

  def update(conn, %{"username" => username, "level" => level}) do
    package = conn.assigns.package
    user = Users.get_by_username(username, [:emails, :organization])

    if is_nil(user) do
      conn
      |> put_flash(:error, "User \"#{username}\" not found.")
      |> redirect(to: ViewHelpers.path_for_owners(package))
    else
      case Owners.update_level(package, user, level, audit: audit_data(conn)) do
        {:ok, _} ->
          conn
          |> put_flash(:info, "#{username}'s role updated to #{level}.")
          |> redirect(to: redirect_after_mutation(conn, package, user, level))

        {:error, :not_owner} ->
          conn
          |> put_flash(:error, "#{username} is not an owner of this package.")
          |> redirect(to: ViewHelpers.path_for_owners(package))

        {:error, :last_full_owner} ->
          conn
          |> put_flash(:error, "Cannot demote the last full owner of a package.")
          |> redirect(to: ViewHelpers.path_for_owners(package))

        {:error, changeset} ->
          conn
          |> put_flash(:error, changeset_error_to_string(changeset))
          |> redirect(to: ViewHelpers.path_for_owners(package))
      end
    end
  end

  def delete(conn, %{"username" => username}) do
    package = conn.assigns.package
    user = Users.get_by_username(username)

    if is_nil(user) do
      conn
      |> put_flash(:error, "User \"#{username}\" not found.")
      |> redirect(to: ViewHelpers.path_for_owners(package))
    else
      case Owners.remove(package, user, audit: audit_data(conn)) do
        :ok ->
          conn
          |> put_flash(:info, "#{username} removed from owners.")
          |> redirect(to: redirect_after_mutation(conn, package, user, nil))

        {:error, :last_owner} ->
          conn
          |> put_flash(:error, "Cannot remove the last owner of a package.")
          |> redirect(to: ViewHelpers.path_for_owners(package))

        {:error, :last_full_owner} ->
          conn
          |> put_flash(:error, "Cannot remove the last full owner of a package.")
          |> redirect(to: ViewHelpers.path_for_owners(package))

        {:error, :not_owner} ->
          conn
          |> put_flash(:error, "#{username} is not an owner of this package.")
          |> redirect(to: ViewHelpers.path_for_owners(package))
      end
    end
  end

  defp redirect_after_mutation(conn, package, target_user, new_level) do
    current_user = conn.assigns.current_user

    if target_user.id == current_user.id and new_level != "full" do
      ViewHelpers.path_for_package(package)
    else
      ViewHelpers.path_for_owners(package)
    end
  end

  defp fetch_package(conn, _opts) do
    name = conn.params["name"]
    repository = Repositories.get(conn.params["repository"], [:organization])
    package = repository && Packages.get(repository, name)

    if package do
      conn
      |> assign(:repository, repository)
      |> assign(:package, package)
    else
      conn
      |> render_error(404, message: "Package not found")
      |> halt()
    end
  end

  defp requires_full_owner(conn, _opts) do
    package = conn.assigns.package
    current_user = conn.assigns.current_user

    if current_user && Packages.owner_with_access?(package, current_user, "full") do
      conn
    else
      conn
      |> render_error(403, message: "You must be a full owner of this package")
      |> halt()
    end
  end

  defp changeset_error_to_string(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(", ", fn {_field, errors} -> Enum.join(errors, ", ") end)
  end
end
