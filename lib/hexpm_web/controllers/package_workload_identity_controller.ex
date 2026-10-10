defmodule HexpmWeb.PackageWorkloadIdentityController do
  use HexpmWeb, :controller

  alias HexpmWeb.{PackageLayoutAssigns, RepositoryAccess, SSOEnforcement, ViewHelpers}

  plug :feature_enabled
  plug :requires_login
  plug :fetch_package
  plug :requires_full_owner
  plug :requires_tfa
  plug HexpmWeb.Plugs.Sudo

  def index(conn, _params) do
    package = conn.assigns.package
    render_index(conn, package, WorkloadIdentity.changeset(%WorkloadIdentity{}, %{}, package))
  end

  def create(conn, params) do
    package = conn.assigns.package
    params = params["workload_identity"] || %{}

    case WorkloadIdentities.create(package, params,
           audit: audit_data(conn),
           before_lookup: fn -> lookup_allowed(conn.assigns.current_user) end
         ) do
      {:ok, _workload_identity} ->
        conn
        |> put_flash(:info, "Workload identity added.")
        |> redirect(to: ViewHelpers.path_for_workload_identities(package))

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(400)
        |> render_index(package, changeset)

      {:error, :not_allowed} ->
        conn
        |> put_flash(
          :error,
          "Workload identities for private packages are managed on the organization's Workload identities page."
        )
        |> redirect(to: ~p"/dashboard/orgs/#{package.repository.name}/workload-identities")

      {:error, :rate_limited} ->
        conn
        |> put_flash(
          :error,
          "Too many attempts to add a workload identity in the last hour. Try again later."
        )
        |> redirect(to: ViewHelpers.path_for_workload_identities(package))

      {:error, :not_owner} ->
        render_error(conn, 403, message: "You must be a full owner of this package")

      {:error, :unknown_provider} ->
        conn
        |> put_flash(:error, "The provider is invalid.")
        |> redirect(to: ViewHelpers.path_for_workload_identities(package))

      {:error, :repository_not_found} ->
        conn
        |> put_flash(:error, "The GitHub repository could not be resolved.")
        |> redirect(to: ViewHelpers.path_for_workload_identities(package))

      {:error, _reason} ->
        conn
        |> put_flash(:error, "GitHub could not be reached, try again later.")
        |> redirect(to: ViewHelpers.path_for_workload_identities(package))
    end
  end

  def delete(conn, %{"id" => id}) do
    package = conn.assigns.package

    case WorkloadIdentities.get(package, id) do
      nil ->
        conn
        |> render_error(404, message: "Workload identity not found")
        |> halt()

      workload_identity ->
        {:ok, _} = WorkloadIdentities.delete(workload_identity, audit: audit_data(conn))

        conn
        |> put_flash(:info, "Workload identity removed.")
        |> redirect(to: ViewHelpers.path_for_workload_identities(package))
    end
  end

  defp render_index(conn, package, changeset) do
    render(
      conn,
      "index.html",
      [
        title: "Workload identities – #{package.name}",
        container: "container",
        workload_identities: WorkloadIdentities.list(package),
        organization_identities: WorkloadIdentities.list_covering(package),
        changeset: changeset
      ] ++ PackageLayoutAssigns.for_package(conn, package)
    )
  end

  defp lookup_allowed(user) do
    case HexpmWeb.Plugs.Attack.workload_identity_lookup_throttle(user.id) do
      {:allow, _data} -> :ok
      {:block, _data} -> {:error, :rate_limited}
    end
  end

  defp feature_enabled(conn, _opts) do
    if WorkloadIdentities.enabled?() do
      conn
    else
      conn
      |> render_error(404, message: "Page not found")
      |> halt()
    end
  end

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

  defp requires_full_owner(conn, _opts) do
    package = conn.assigns.package
    current_user = conn.assigns.current_user

    if current_user && Packages.owner_with_access?(package, current_user, "full") do
      case SSOEnforcement.check_package(conn, package, current_user, "full") do
        :ok -> conn
        {:error, refusal, organization} -> SSOEnforcement.refuse(conn, refusal, organization)
      end
    else
      conn
      |> render_error(403, message: "You must be a full owner of this package")
      |> halt()
    end
  end

  defp requires_tfa(conn, _opts) do
    current_user = conn.assigns.current_user

    if User.tfa_enabled?(current_user) do
      conn
    else
      conn
      |> render_error(403,
        message:
          "Two-factor authentication is required to manage workload identities. " <>
            "Enable 2FA in your security settings (/dashboard/security) and try again."
      )
      |> halt()
    end
  end
end
