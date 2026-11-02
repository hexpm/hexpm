defmodule HexpmWeb.PackagePublishApprovalController do
  use HexpmWeb, :controller

  alias Hexpm.Repository.StagedReleases
  alias HexpmWeb.{PackageLayoutAssigns, RepositoryAccess, SSOEnforcement, ViewHelpers}

  plug :requires_login
  plug :fetch_package
  plug :authorize_settings
  plug HexpmWeb.Plugs.Sudo, force: true

  def show(conn, _params), do: render_show(conn)
  def enable(conn, _params), do: configure(conn, true)
  def disable(conn, _params), do: configure(conn, false)

  defp configure(conn, enabled) do
    case StagedReleases.configure(conn.assigns.package, conn.assigns.current_user, enabled,
           audit: audit_data(conn),
           session_id: conn.assigns.current_session.id
         ) do
      {:ok, package} ->
        conn
        |> put_flash(:info, "Publish approval setting updated.")
        |> redirect(to: ViewHelpers.path_for_publish_approval(package))

      {:error, :tfa_required} ->
        render_error(conn, 403,
          message: "Enable two-factor authentication before configuring publish approval."
        )

      {:error, :forbidden} ->
        render_error(conn, 403, message: "You can't configure this setting.")
    end
  end

  defp fetch_package(conn, _opts) do
    case RepositoryAccess.fetch_package(conn, conn.params["repository"], conn.params["name"]) do
      {:ok, package} ->
        if StagedReleases.enabled?(package),
          do: assign(conn, :package, package),
          else: conn |> not_found() |> halt()

      {:error, requirement, organization} when requirement in [:sso_required, :tfa_required] ->
        SSOEnforcement.refuse(conn, requirement, organization)

      :error ->
        conn |> not_found() |> halt()
    end
  end

  defp authorize_settings(conn, _opts) do
    case {RepositoryAccess.package_settings(conn, conn.assigns.package), action_name(conn)} do
      {{:ok, :manage}, _} ->
        assign(conn, :manage?, true)

      {{:ok, :view}, :show} ->
        assign(conn, :manage?, false)

      {{:error, refusal, organization}, _} ->
        SSOEnforcement.refuse(conn, refusal, organization)

      _ ->
        conn |> render_error(403, message: "You must be a full owner of this package") |> halt()
    end
  end

  defp render_show(conn) do
    render(
      conn,
      :show,
      [title: "Publish approval", container: "container"] ++
        PackageLayoutAssigns.for_package(conn, conn.assigns.package)
    )
  end
end
