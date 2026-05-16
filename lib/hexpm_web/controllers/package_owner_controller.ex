defmodule HexpmWeb.PackageOwnerController do
  use HexpmWeb, :controller

  plug :requires_login
  plug :fetch_package
  plug :requires_full_owner
  plug HexpmWeb.Plugs.Sudo

  def index(conn, _params) do
    package = conn.assigns.package
    owners = Owners.all(package, user: [:emails, :organization])

    render(
      conn,
      "index.html",
      [
        title: "Manage owners – #{package.name}",
        container: "container",
        package: package,
        owners: owners
      ] ++ package_layout_assigns(conn, package)
    )
  end

  def create(conn, %{"username" => username} = params) do
    package = conn.assigns.package
    user = Users.get_by_username(username, [:emails, :organization])

    if is_nil(user) do
      conn
      |> put_flash(:error, "User \"#{username}\" not found.")
      |> redirect(to: ~p"/packages/#{package.name}/owners")
    else
      case Owners.add(package, user, params, audit: audit_data(conn)) do
        {:ok, _} ->
          conn
          |> put_flash(:info, "#{username} added as owner.")
          |> redirect(to: ~p"/packages/#{package.name}/owners")

        {:error, :not_member} ->
          conn
          |> put_flash(:error, "#{username} is not a member of this repository.")
          |> redirect(to: ~p"/packages/#{package.name}/owners")

        {:error, :not_organization_transfer} ->
          conn
          |> put_flash(:error, "#{username} is an organization — use a transfer to add it.")
          |> redirect(to: ~p"/packages/#{package.name}/owners")

        {:error, :organization_level} ->
          conn
          |> put_flash(:error, "Organizations must be added as full owners.")
          |> redirect(to: ~p"/packages/#{package.name}/owners")

        {:error, :organization_user_conflict} ->
          conn
          |> put_flash(:error, "#{username} conflicts with an existing organization owner.")
          |> redirect(to: ~p"/packages/#{package.name}/owners")

        {:error, :last_full_owner} ->
          conn
          |> put_flash(:error, "Cannot demote the last full owner of a package.")
          |> redirect(to: ~p"/packages/#{package.name}/owners")

        {:error, changeset} ->
          conn
          |> put_flash(:error, changeset_error_to_string(changeset))
          |> redirect(to: ~p"/packages/#{package.name}/owners")
      end
    end
  end

  def update(conn, %{"username" => username, "level" => level}) do
    package = conn.assigns.package
    user = Users.get_by_username(username, [:emails, :organization])

    if is_nil(user) do
      conn
      |> put_flash(:error, "User \"#{username}\" not found.")
      |> redirect(to: ~p"/packages/#{package.name}/owners")
    else
      case Owners.update_level(package, user, level, audit: audit_data(conn)) do
        {:ok, _} ->
          conn
          |> put_flash(:info, "#{username}'s role updated to #{level}.")
          |> redirect(to: redirect_after_mutation(conn, package, user, level))

        {:error, :not_owner} ->
          conn
          |> put_flash(:error, "#{username} is not an owner of this package.")
          |> redirect(to: ~p"/packages/#{package.name}/owners")

        {:error, :last_full_owner} ->
          conn
          |> put_flash(:error, "Cannot demote the last full owner of a package.")
          |> redirect(to: ~p"/packages/#{package.name}/owners")

        {:error, changeset} ->
          conn
          |> put_flash(:error, changeset_error_to_string(changeset))
          |> redirect(to: ~p"/packages/#{package.name}/owners")
      end
    end
  end

  def delete(conn, %{"username" => username}) do
    package = conn.assigns.package
    user = Users.get_by_username(username)

    if is_nil(user) do
      conn
      |> put_flash(:error, "User \"#{username}\" not found.")
      |> redirect(to: ~p"/packages/#{package.name}/owners")
    else
      case Owners.remove(package, user, audit: audit_data(conn)) do
        :ok ->
          conn
          |> put_flash(:info, "#{username} removed from owners.")
          |> redirect(to: redirect_after_mutation(conn, package, user, nil))

        {:error, :last_owner} ->
          conn
          |> put_flash(:error, "Cannot remove the last owner of a package.")
          |> redirect(to: ~p"/packages/#{package.name}/owners")

        {:error, :last_full_owner} ->
          conn
          |> put_flash(:error, "Cannot remove the last full owner of a package.")
          |> redirect(to: ~p"/packages/#{package.name}/owners")

        {:error, :not_owner} ->
          conn
          |> put_flash(:error, "#{username} is not an owner of this package.")
          |> redirect(to: ~p"/packages/#{package.name}/owners")
      end
    end
  end

  defp redirect_after_mutation(conn, package, target_user, new_level) do
    current_user = conn.assigns.current_user

    if target_user.id == current_user.id and new_level != "full" do
      ~p"/packages/#{package.name}"
    else
      ~p"/packages/#{package.name}/owners"
    end
  end

  defp package_layout_assigns(conn, package) do
    releases = Releases.all(package)

    current_release =
      case Release.latest_version(releases, only_stable: true, unstable_fallback: true) do
        nil -> nil
        release -> Releases.preload(release, [:requirements, :downloads, :publisher])
      end

    latest_release_with_docs =
      Release.latest_version(releases,
        only_stable: true,
        unstable_fallback: true,
        with_docs: true
      )

    docs_html_url =
      Hexpm.Utils.current_docs_html_url(package, current_release, latest_release_with_docs)

    repositories =
      Users.all_organizations(conn.assigns.current_user)
      |> Enum.map(& &1.repository)

    dependants_count = Packages.count_dependants(repositories, package)

    last_download_day =
      Hexpm.Cache.fetch(:last_download_day, &Downloads.last_day/0) || Date.utc_today()

    start_day = Date.add(last_download_day, -30)

    graph_downloads =
      Downloads.for_period(package, :day, downloads_after: start_day)
      |> Map.new(&{Date.from_iso8601!(&1.day), &1})

    daily_graph =
      Enum.map(Date.range(start_day, last_download_day), fn day ->
        if dl = graph_downloads[day], do: dl.downloads, else: 0
      end)

    [
      current_release: current_release,
      current_user: conn.assigns.current_user,
      daily_graph: daily_graph,
      dependants_count: dependants_count,
      docs_html_url: docs_html_url,
      downloads: Downloads.package(package),
      graph_release: nil,
      repository_name: package.repository.name,
      versions_count: Enum.count(releases)
    ]
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
