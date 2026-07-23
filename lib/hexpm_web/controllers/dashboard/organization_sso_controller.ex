defmodule HexpmWeb.Dashboard.OrganizationSSOController do
  use HexpmWeb, :controller

  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.Error

  plug :requires_login
  plug HexpmWeb.Plugs.Sudo

  def configure(conn, %{"dashboard_org" => name, "sso" => params}) do
    with_organization(conn, name, fn organization ->
      case SSO.configure(organization, params, audit: audit_data(conn)) do
        {:ok, _connection} ->
          redirect_with_flash(
            conn,
            organization,
            :info,
            "SSO configuration was saved. Test it before enabling login."
          )

        {:error, reason} ->
          redirect_with_flash(conn, organization, :error, configuration_error(reason))
      end
    end)
  end

  def test(conn, %{"dashboard_org" => name} = params) do
    with_organization(conn, name, fn organization ->
      secret_slot = params["secret_slot"] || "active"

      case SSO.start_test(organization, conn.assigns.current_user, secret_slot, callback_url()) do
        {:ok, transaction, uri} ->
          conn
          |> remember_sso_state(transaction.raw_state)
          |> redirect(external: uri)

        {:error, reason} ->
          redirect_with_flash(conn, organization, :error, test_error(reason))
      end
    end)
  end

  def enable(conn, %{"dashboard_org" => name}) do
    with_organization(conn, name, fn organization ->
      case SSO.enable(organization, audit: audit_data(conn)) do
        {:ok, _connection} ->
          redirect_with_flash(conn, organization, :info, "SSO login was enabled.")

        {:error, reason} ->
          redirect_with_flash(conn, organization, :error, enable_error(reason))
      end
    end)
  end

  def disable(conn, %{"dashboard_org" => name}) do
    with_organization(conn, name, fn organization ->
      case SSO.disable(organization, audit: audit_data(conn)) do
        {:ok, _connection} ->
          redirect_with_flash(conn, organization, :info, "SSO login was disabled immediately.")

        {:error, reason} ->
          redirect_with_flash(conn, organization, :error, configuration_error(reason))
      end
    end)
  end

  def rotate(conn, %{"dashboard_org" => name, "sso" => %{"client_secret" => secret}}) do
    with_organization(conn, name, fn organization ->
      case SSO.begin_rotation(organization, secret, audit: audit_data(conn)) do
        {:ok, _connection} ->
          redirect_with_flash(
            conn,
            organization,
            :info,
            "The replacement secret was saved. Test it before completing rotation."
          )

        {:error, reason} ->
          redirect_with_flash(conn, organization, :error, rotation_error(reason))
      end
    end)
  end

  def rotate(conn, %{"dashboard_org" => name}) do
    with_organization(conn, name, fn organization ->
      redirect_with_flash(conn, organization, :error, "Enter a replacement client secret.")
    end)
  end

  def promote(conn, %{"dashboard_org" => name}) do
    with_organization(conn, name, fn organization ->
      case SSO.promote_rotation(organization, audit: audit_data(conn)) do
        {:ok, _connection} ->
          redirect_with_flash(conn, organization, :info, "Client secret rotation was completed.")

        {:error, reason} ->
          redirect_with_flash(conn, organization, :error, rotation_error(reason))
      end
    end)
  end

  def unlink(conn, %{"dashboard_org" => name, "user_id" => user_id}) do
    with_organization(conn, name, fn organization ->
      user = Users.get_by_id(safe_to_integer(user_id), [:emails])

      if user do
        case SSO.unlink_identity(organization, user, audit: audit_data(conn)) do
          {:ok, %Hexpm.Accounts.SSO.Identity{}} ->
            redirect_with_flash(conn, organization, :info, "The SSO identity was unlinked.")

          {:ok, nil} ->
            not_found(conn)

          {:error, reason} ->
            redirect_with_flash(conn, organization, :error, configuration_error(reason))
        end
      else
        not_found(conn)
      end
    end)
  end

  defp with_organization(conn, name, fun) do
    user = conn.assigns.current_user
    organization = Organizations.get(name)

    cond do
      is_nil(organization) ->
        not_found(conn)

      not SSO.enabled?(organization) ->
        not_found(conn)

      Organizations.get_role(organization, user) != "admin" ->
        conn
        |> put_flash(:error, "You do not have permission for this action.")
        |> redirect(to: ~p"/dashboard/orgs/#{organization}")

      true ->
        fun.(organization)
    end
  end

  defp redirect_with_flash(conn, organization, level, message) do
    conn
    |> put_flash(level, message)
    |> redirect(to: ~p"/dashboard/orgs/#{organization}/sso")
  end

  defp callback_url, do: url(~p"/sso/callback")

  defp configuration_error(%Error{code: code}),
    do: "SSO configuration could not be validated (#{code})."

  defp configuration_error(:connection_enabled),
    do:
      "Disable SSO before changing the issuer or client ID. Use secret rotation to replace an enabled connection's secret."

  defp configuration_error(:connection_has_identities),
    do: "Unlink every account before changing the configured issuer."

  defp configuration_error(:admin_required), do: "Organization administrator access is required."

  defp configuration_error(%Ecto.Changeset{}),
    do: "Enter a valid issuer URL, client ID, and client secret."

  defp configuration_error(_reason), do: "The SSO configuration could not be changed."

  defp test_error(%Error{code: code}), do: "SSO connection test could not start (#{code})."

  defp test_error(:configuration_admin_required),
    do:
      "The administrator who saved the configuration must complete its connection test. If that administrator is unavailable, disable SSO if needed and have a current administrator save the configuration again."

  defp test_error(:rotation_not_started), do: "Save a replacement secret before testing it."
  defp test_error(reason), do: configuration_error(reason)

  defp enable_error(:connection_not_tested),
    do: "Complete a successful connection test before enabling SSO."

  defp enable_error(reason), do: configuration_error(reason)

  defp rotation_error(:rotation_not_ready),
    do: "Test the replacement secret before completing rotation."

  defp rotation_error(%Ecto.Changeset{}), do: "Enter a valid replacement client secret."
  defp rotation_error(reason), do: configuration_error(reason)
end
