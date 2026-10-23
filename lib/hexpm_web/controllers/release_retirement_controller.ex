defmodule HexpmWeb.ReleaseRetirementController do
  use HexpmWeb, :controller

  alias HexpmWeb.{PackageLayoutAssigns, RepositoryAccess, SSOEnforcement, ViewHelpers}

  plug :requires_login
  plug :fetch_package
  plug :authorize_retirement
  plug :fetch_release when action in [:show, :create, :delete]
  plug :requires_tfa when action in [:create, :delete, :create_all]
  plug HexpmWeb.Plugs.Sudo

  def show(conn, _params) do
    retirement = conn.assigns.release.retirement || %ReleaseRetirement{}
    render_show(conn, ReleaseRetirement.changeset(retirement, %{}))
  end

  def create(conn, params) do
    %{package: package, release: release} = conn.assigns
    params = retirement_params(params)
    changeset = retirement_changeset(params)

    if changeset.valid? do
      :ok = Releases.retire(package, release, params, audit: audit_data(conn))

      conn
      |> put_flash(:info, "#{package.name} #{release.version} has been retired.")
      |> redirect(to: ViewHelpers.path_for_releases(package))
    else
      conn
      |> put_status(400)
      |> render_show(%{changeset | action: :insert})
    end
  end

  def delete(conn, _params) do
    %{package: package, release: release} = conn.assigns

    if release.retirement do
      :ok = Releases.unretire(package, release, audit: audit_data(conn))

      conn
      |> put_flash(:info, "#{package.name} #{release.version} is no longer retired.")
      |> redirect(to: ViewHelpers.path_for_releases(package))
    else
      conn
      |> put_flash(:info, "#{package.name} #{release.version} is not retired.")
      |> redirect(to: ViewHelpers.path_for_releases(package))
    end
  end

  def show_all(conn, _params) do
    render_show_all(conn, ReleaseRetirement.changeset(%ReleaseRetirement{}, %{}), false)
  end

  def create_all(conn, params) do
    package = conn.assigns.package
    replace? = params["replace"] == "true"
    params = retirement_params(params)
    changeset = retirement_changeset(params)

    if changeset.valid? do
      {:ok, count} =
        Releases.retire(package, params, audit: audit_data(conn), replace: replace?)

      conn
      |> put_flash(:info, retired_all_message(package, count))
      |> redirect(to: ViewHelpers.path_for_releases(package))
    else
      conn
      |> put_status(400)
      |> render_show_all(%{changeset | action: :insert}, replace?)
    end
  end

  defp retirement_params(params) do
    case params["retirement"] do
      %{} = retirement -> Map.take(retirement, ["reason", "message"])
      _ -> %{}
    end
  end

  # The message is required here as it is by `mix hex.retire`, though the API
  # accepts a retirement without one.
  defp retirement_changeset(params) do
    %ReleaseRetirement{}
    |> ReleaseRetirement.changeset(params)
    |> Ecto.Changeset.validate_required([:message])
  end

  defp retired_all_message(package, 0), do: "All versions of #{package.name} are already retired."
  defp retired_all_message(package, 1), do: "Retired 1 version of #{package.name}."
  defp retired_all_message(package, count), do: "Retired #{count} versions of #{package.name}."

  defp render_show_all(conn, changeset, replace?) do
    package = conn.assigns.package
    releases = Releases.all(package)
    retired_count = Enum.count(releases, & &1.retirement)

    render(
      conn,
      "show_all.html",
      [
        title: "Retire all versions of #{package.name}",
        container: "container",
        changeset: changeset,
        replace?: replace?,
        retired_count: retired_count,
        active_count: length(releases) - retired_count,
        tfa?: User.tfa_enabled?(conn.assigns.current_user)
      ] ++ PackageLayoutAssigns.for_package(conn, package, releases: releases)
    )
  end

  defp render_show(conn, changeset) do
    %{package: package, release: release} = conn.assigns
    releases = Releases.all(package)
    release = Releases.preload(release, [:requirements, :downloads, :publisher])

    render(
      conn,
      "show.html",
      [
        title: "Retire #{package.name} #{release.version}",
        container: "container",
        release: release,
        changeset: changeset,
        tfa?: User.tfa_enabled?(conn.assigns.current_user)
      ] ++
        PackageLayoutAssigns.for_package(conn, package,
          releases: releases,
          current_release: release,
          graph_release: release
        )
    )
  end

  # A repository the caller does not reach answers exactly as a missing package
  # does, so private package names are not disclosed.
  defp fetch_package(conn, _opts) do
    case RepositoryAccess.fetch_package(conn, conn.params["repository"], conn.params["name"]) do
      {:ok, package} ->
        conn
        |> assign(:repository, package.repository)
        |> assign(:package, package)

      {:error, requirement, organization} when requirement in [:sso_required, :tfa_required] ->
        SSOEnforcement.refuse(conn, :sso_required, organization)

      :error ->
        conn
        |> render_error(404, message: "Package not found")
        |> halt()
    end
  end

  # The same access the API's retirement endpoints require: a maintainer or full
  # owner, a member with write access of an organization that owns the package,
  # or a member with write access of a private package's organization.
  defp authorize_retirement(conn, _opts) do
    %{package: package, current_user: user} = conn.assigns

    if Packages.owner_with_access?(package, user, "maintainer") do
      case SSOEnforcement.check_package(conn, package, user, "maintainer") do
        :ok -> conn
        {:error, refusal, organization} -> SSOEnforcement.refuse(conn, refusal, organization)
      end
    else
      conn
      |> render_error(403, message: "You must be an owner of this package to retire its versions")
      |> halt()
    end
  end

  defp fetch_release(conn, _opts) do
    with {:ok, version} <- Version.parse(conn.params["version"]),
         %Release{} = release <- Releases.get(conn.assigns.package, version) do
      assign(conn, :release, release)
    else
      _ ->
        conn
        |> render_error(404, message: "Version not found")
        |> halt()
    end
  end

  defp requires_tfa(conn, _opts) do
    if User.tfa_enabled?(conn.assigns.current_user) do
      conn
    else
      conn
      |> render_error(403,
        message:
          "Two-factor authentication is required to retire and unretire versions. " <>
            "Enable 2FA in your security settings (/dashboard/security) and try again."
      )
      |> halt()
    end
  end
end
