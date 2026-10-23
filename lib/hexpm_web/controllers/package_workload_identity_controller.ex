defmodule HexpmWeb.PackageWorkloadIdentityController do
  use HexpmWeb, :controller

  alias HexpmWeb.{PackageLayoutAssigns, RepositoryAccess, SSOEnforcement, ViewHelpers}

  plug :requires_login
  plug :fetch_package
  plug :feature_enabled
  plug :authorize_settings
  plug :requires_tfa when action in [:create, :edit, :update, :delete]
  plug HexpmWeb.Plugs.Sudo

  def index(conn, _params) do
    package = conn.assigns.package
    render_index(conn, package, WorkloadIdentity.changeset(%WorkloadIdentity{}, %{}, package))
  end

  def edit(conn, %{"id" => id}) do
    package = conn.assigns.package

    with {:ok, workload_identity} <- fetch_workload_identity(conn, package, id) do
      render_index(
        conn,
        package,
        WorkloadIdentity.update_changeset(workload_identity, %{}),
        workload_identity
      )
    end
  end

  def update(conn, %{"id" => id} = params) do
    package = conn.assigns.package

    with {:ok, workload_identity} <- fetch_workload_identity(conn, package, id) do
      case WorkloadIdentities.update(workload_identity, params["workload_identity"] || %{},
             audit: audit_data(conn),
             before_lookup: &lookup_allowed(conn.assigns.current_user, &1)
           ) do
        {:ok, _workload_identity} ->
          conn
          |> put_flash(:info, "Workload identity saved.")
          |> redirect(to: ViewHelpers.path_for_workload_identities(package))

        {:error, %Ecto.Changeset{} = changeset} ->
          conn
          |> put_status(400)
          |> render_index(package, changeset, workload_identity)

        {:error, :not_found} ->
          conn
          |> render_error(404, message: "Workload identity not found")
          |> halt()

        {:error, :changed} ->
          conn
          |> put_flash(
            :error,
            "Someone else changed the workload identity while you were editing it. Review it and save again."
          )
          |> redirect(
            to: ViewHelpers.path_for_workload_identity(package, workload_identity.id) <> "/edit"
          )

        {:error, reason} ->
          lookup_error(conn, package, reason, "change")
      end
    end
  end

  defp fetch_workload_identity(conn, package, id) do
    case WorkloadIdentities.get(package, id) do
      nil ->
        conn
        |> render_error(404, message: "Workload identity not found")
        |> halt()

      workload_identity ->
        {:ok, %{workload_identity | package: package}}
    end
  end

  def create(conn, params) do
    package = conn.assigns.package
    params = params["workload_identity"] || %{}

    case WorkloadIdentities.create(package, params,
           audit: audit_data(conn),
           before_lookup: &lookup_allowed(conn.assigns.current_user, &1)
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

      {:error, reason} ->
        lookup_error(conn, package, reason, "add")
    end
  end

  defp lookup_error(conn, _package, :not_owner, _verb),
    do: render_error(conn, 403, message: "You must be a full owner of this package")

  defp lookup_error(conn, package, reason, verb) do
    message =
      case reason do
        :rate_limited ->
          "Too many attempts to #{verb} a workload identity in the last hour. Try again later."

        :unknown_provider ->
          "The provider is invalid."

        :repository_not_found ->
          "The GitHub repository could not be resolved."

        _reason ->
          "GitHub could not be reached, try again later."
      end

    conn
    |> put_flash(:error, message)
    |> redirect(to: ViewHelpers.path_for_workload_identities(package))
  end

  def delete(conn, %{"id" => id}) do
    package = conn.assigns.package

    with %WorkloadIdentity{} = workload_identity <- WorkloadIdentities.get(package, id),
         {:ok, _deleted} <- WorkloadIdentities.delete(workload_identity, audit: audit_data(conn)) do
      conn
      |> put_flash(:info, "Workload identity removed.")
      |> redirect(to: ViewHelpers.path_for_workload_identities(package))
    else
      _not_found ->
        conn
        |> render_error(404, message: "Workload identity not found")
        |> halt()
    end
  end

  defp render_index(conn, package, changeset, editing \\ nil) do
    render(
      conn,
      "index.html",
      [
        title: "Workload identities – #{package.name}",
        container: "container",
        workload_identities: WorkloadIdentities.list(package),
        organization_identities: WorkloadIdentities.list_covering(package),
        changeset: changeset,
        editing: editing,
        tfa?: User.tfa_enabled?(conn.assigns.current_user)
      ] ++ PackageLayoutAssigns.for_package(conn, package)
    )
  end

  # Every save counts, and so does every GitHub call its lookup can make.
  defp lookup_allowed(user, calls) do
    with {:allow, _data} <- HexpmWeb.Plugs.Attack.workload_identity_lookup_throttle(user.id),
         {:allow, _data} <-
           HexpmWeb.Plugs.Attack.workload_identity_github_throttle(user.id, calls) do
      :ok
    else
      {:block, _data} -> {:error, :rate_limited}
    end
  end

  defp feature_enabled(conn, _opts) do
    if WorkloadIdentities.enabled?(conn.assigns.package) do
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

  defp authorize_settings(conn, _opts) do
    case {RepositoryAccess.package_settings(conn, conn.assigns.package), action_name(conn)} do
      {{:ok, :manage}, _action} ->
        assign(conn, :manage?, true)

      {{:ok, :view}, :index} ->
        assign(conn, :manage?, false)

      {{:error, refusal, organization}, _action} ->
        SSOEnforcement.refuse(conn, refusal, organization)

      _ ->
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
