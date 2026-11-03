defmodule HexpmWeb.StagedPublishingController do
  use HexpmWeb, :controller

  alias Hexpm.Repository.StagedReleases

  plug :requires_login
  plug :fetch_policy_organization
  plug HexpmWeb.Plugs.OrganizationSSO
  plug :require_settings_sudo when action == :show
  plug HexpmWeb.Plugs.Sudo when action == :enable
  plug HexpmWeb.Plugs.Sudo, [force: true] when action == :disable

  def show(conn, _params), do: render_show(conn)
  def enable(conn, _params), do: configure(conn, true)
  def disable(conn, _params), do: configure(conn, false)

  defp configure(conn, enabled) do
    case StagedReleases.configure(conn.assigns.organization, conn.assigns.current_user, enabled,
           audit: audit_data(conn),
           session_id: conn.assigns.current_session.id
         ) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Staged publishing policy updated.")
        |> redirect(to: ~p"/dashboard/orgs/#{conn.assigns.organization}/staged-publishing")

      {:error, :tfa_required} ->
        render_error(conn, 403,
          message: "Enable two-factor authentication before configuring staged publishing."
        )

      {:error, :forbidden} ->
        render_error(conn, 403, message: "You can't configure this policy.")
    end
  end

  defp fetch_policy_organization(conn, _opts) do
    organization =
      Organizations.get(conn.params["dashboard_org"], [:repository, :organization_users])

    if organization && organization.id != 1 &&
         StagedReleases.enabled?(organization) &&
         Organizations.access?(organization, conn.assigns.current_user, "admin") do
      assign(conn, :organization, organization)
    else
      conn |> not_found() |> halt()
    end
  end

  defp require_settings_sudo(conn, _opts) do
    HexpmWeb.Plugs.Sudo.call(conn, force: conn.assigns.organization.require_staged_publishing)
  end

  defp render_show(conn) do
    render(conn, :show,
      title: "Staged publishing",
      container: "container page dashboard",
      sidebar: :organization,
      tab: :staged_publishing
    )
  end
end
