defmodule HexpmWeb.Dashboard.OrganizationSSOController do
  use HexpmWeb, :controller

  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.Error
  alias HexpmWeb.SSOEnforcement

  plug :requires_login

  # These are carved out of the SSO gate, so a stolen account session reaches
  # them without ever touching the provider. Chained, they replace the
  # organization's provider with one the attacker controls: disable, unlink
  # every identity, point the connection at another issuer, enable, link.
  # Setting enforcement back to optional takes the gate off every member in one
  # step and without touching the provider at all. Each of them takes a fresh
  # password rather than the rolling window login grants.
  plug HexpmWeb.Plugs.Sudo,
       [force: true]
       when action in [
              :configure,
              :enable,
              :disable,
              :delete,
              :rotate,
              :promote,
              :unlink,
              :configure_enforcement
            ]

  plug HexpmWeb.Plugs.Sudo

  # Repairing the connection is what break-glass is for, and turning enforcement
  # off is part of repairing it: it is one switch, organization-wide, audited,
  # and visible on the screen that shows it. Exempting a single member is not.
  # It outlives the outage, leaves the organization reading as enforced, and an
  # administrator locked out by their own provider could quietly write
  # themselves out of enforcement with it.
  plug HexpmWeb.Plugs.OrganizationSSO,
    except: [
      :configure,
      :test,
      :enable,
      :disable,
      :delete,
      :rotate,
      :promote,
      :unlink,
      :configure_jit,
      :configure_enforcement,
      :add_domain,
      :verify_domain,
      :remove_domain
    ]

  def configure(conn, %{"dashboard_org" => name, "sso" => params}) do
    with_organization(conn, name, fn organization ->
      redirect_result(
        conn,
        organization,
        SSO.configure(organization, params, audit: audit_data(conn)),
        "SSO configuration was saved. Test it before enabling login.",
        &configuration_error/1
      )
    end)
  end

  def test(conn, %{"dashboard_org" => name} = params) do
    with_organization(conn, name, fn organization ->
      secret_slot = params["secret_slot"] || "active"

      case SSO.start_test(
             organization,
             conn.assigns.current_user,
             secret_slot,
             SSOEnforcement.callback_url()
           ) do
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
      redirect_result(
        conn,
        organization,
        SSO.enable(organization, audit: audit_data(conn)),
        "SSO login was enabled.",
        &enable_error/1
      )
    end)
  end

  def disable(conn, %{"dashboard_org" => name}) do
    with_organization(conn, name, fn organization ->
      redirect_result(
        conn,
        organization,
        SSO.disable(organization, audit: audit_data(conn)),
        "SSO login was disabled immediately.",
        &configuration_error/1
      )
    end)
  end

  def delete(conn, %{"dashboard_org" => name}) do
    with_organization(conn, name, fn organization ->
      redirect_result(
        conn,
        organization,
        SSO.delete_connection(organization, audit: audit_data(conn)),
        "The SSO configuration was removed, along with every account linked through it.",
        &delete_error/1
      )
    end)
  end

  def rotate(conn, %{"dashboard_org" => name, "sso" => %{"client_secret" => secret}}) do
    with_organization(conn, name, fn organization ->
      redirect_result(
        conn,
        organization,
        SSO.begin_rotation(organization, secret, audit: audit_data(conn)),
        "The replacement secret was saved. Test it before completing rotation.",
        &rotation_error/1
      )
    end)
  end

  def rotate(conn, %{"dashboard_org" => name}) do
    with_organization(conn, name, fn organization ->
      redirect_with_flash(conn, organization, :error, "Enter a replacement client secret.")
    end)
  end

  def promote(conn, %{"dashboard_org" => name}) do
    with_organization(conn, name, fn organization ->
      redirect_result(
        conn,
        organization,
        SSO.promote_rotation(organization, audit: audit_data(conn)),
        "Client secret rotation was completed.",
        &rotation_error/1
      )
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

  def configure_jit(conn, %{"dashboard_org" => name} = params) do
    with_organization(conn, name, fn organization ->
      redirect_result(
        conn,
        organization,
        SSO.configure_jit(organization, params["jit"] || %{}, audit: audit_data(conn)),
        &jit_message/1,
        &jit_error/1
      )
    end)
  end

  defp jit_message(%{jit_seat_policy: nil}),
    do: "Just-in-time membership is off. Members have to be added or invited."

  defp jit_message(%{jit_seat_policy: "block", jit_role: role}),
    do:
      "Just-in-time membership is on. New members join as #{role}, and logins are refused once the seats run out."

  defp jit_message(%{jit_seat_policy: "expand", jit_role: role}),
    do:
      "Just-in-time membership is on. New members join as #{role}, and the subscription grows by a seat when it needs to."

  defp jit_error(:domain_required),
    do: "Verify a domain before turning on just-in-time membership."

  defp jit_error(:not_configured), do: "Configure SSO before turning on just-in-time membership."

  defp jit_error(%Ecto.Changeset{}),
    do: "Choose what happens when the seats run out, and a role for new members."

  defp jit_error(reason), do: configuration_error(reason)

  def configure_enforcement(conn, %{"dashboard_org" => name} = params) do
    with_organization(conn, name, fn organization ->
      redirect_result(
        conn,
        organization,
        SSO.configure_enforcement(organization, params["enforcement"] || %{},
          audit: audit_data(conn)
        ),
        &enforcement_message/1,
        &enforcement_error/1
      )
    end)
  end

  defp enforcement_message(%{enforcement_mode: "optional"}),
    do: "SSO is optional. Members reach the organization with or without it."

  defp enforcement_message(%{enforcement_mode: "pilot"}),
    do: "SSO is in pilot. Only the members you marked as enforced need it."

  defp enforcement_message(%{enforcement_mode: "required", required_at: required_at}) do
    if DateTime.compare(DateTime.utc_now(), required_at) == :lt do
      "SSO becomes required on #{HexpmWeb.ViewHelpers.pretty_date(required_at)}. Until then only the members you marked as enforced need it."
    else
      "SSO is required. Every member except the exemptions needs it."
    end
  end

  defp enforcement_error(:no_reachable_admin),
    do:
      "At least one administrator has to have linked their identity, or be exempt, before SSO can be required."

  defp enforcement_error(:not_configured), do: "Configure SSO before setting enforcement."

  defp enforcement_error(%Ecto.Changeset{} = changeset) do
    case translate_errors(changeset) do
      %{personal_keys: message} -> "Personal API keys #{message}."
      %{session_lifetime_seconds: message} -> "Session lifetime #{message}."
      _ -> "The enforcement settings could not be saved."
    end
  end

  defp enforcement_error(reason), do: configuration_error(reason)

  def set_member_enforcement(conn, %{"dashboard_org" => name, "user_id" => user_id} = params) do
    with_organization(conn, name, fn organization ->
      case Users.get_by_id(safe_to_integer(user_id) || 0) do
        nil ->
          not_found(conn)

        user ->
          case SSO.set_member_enforcement(organization, user, params["sso_enforcement"],
                 audit: audit_data(conn)
               ) do
            {:ok, _member} ->
              redirect_with_flash(
                conn,
                organization,
                :info,
                member_enforcement_message(user, params["sso_enforcement"])
              )

            {:error, :not_member} ->
              redirect_with_flash(
                conn,
                organization,
                :error,
                "#{user.username} is not a member of this organization."
              )

            {:error, :no_reachable_admin} ->
              redirect_with_flash(
                conn,
                organization,
                :error,
                enforcement_error(:no_reachable_admin)
              )

            {:error, :admin_required} ->
              redirect_with_flash(
                conn,
                organization,
                :error,
                configuration_error(:admin_required)
              )

            {:error, :feature_disabled} ->
              redirect_with_flash(
                conn,
                organization,
                :error,
                "SSO is not available for this organization."
              )

            {:error, _changeset} ->
              redirect_with_flash(
                conn,
                organization,
                :error,
                "That is not an enforcement setting."
              )
          end
      end
    end)
  end

  defp member_enforcement_message(user, "enforced"),
    do: "#{user.username} now needs SSO whatever the mode is."

  defp member_enforcement_message(user, "exempt"),
    do: "#{user.username} is exempt from SSO. Exemptions are listed for administrators to review."

  defp member_enforcement_message(user, _enforcement),
    do: "#{user.username} now follows the organization's enforcement mode."

  def add_domain(conn, %{"dashboard_org" => name, "domain" => params}) do
    with_organization(conn, name, fn organization ->
      redirect_result(
        conn,
        organization,
        OrganizationDomains.add(organization, params, conn.assigns.current_user,
          audit: audit_data(conn)
        ),
        &"#{&1.domain} was added. Publish the TXT record below, then verify it.",
        &domain_error/1
      )
    end)
  end

  def verify_domain(conn, %{"dashboard_org" => name, "domain_id" => id}) do
    with_domain(conn, name, id, fn organization, domain ->
      redirect_result(
        conn,
        organization,
        OrganizationDomains.verify(organization, domain, audit: audit_data(conn)),
        &"#{&1.domain} is verified.",
        &verify_domain_error(domain, &1)
      )
    end)
  end

  def remove_domain(conn, %{"dashboard_org" => name, "domain_id" => id}) do
    with_domain(conn, name, id, fn organization, domain ->
      {:ok, _domain} =
        OrganizationDomains.remove(organization, domain, audit: audit_data(conn))

      redirect_with_flash(conn, organization, :info, "#{domain.domain} was removed.")
    end)
  end

  defp verify_domain_error(domain, :record_not_found) do
    "No matching TXT record was found for #{domain.domain}. DNS changes can take a while to propagate."
  end

  defp verify_domain_error(domain, :lookup_failed) do
    "The DNS lookup for #{domain.domain} did not answer. Try again in a moment."
  end

  defp verify_domain_error(domain, _reason), do: "#{domain.domain} could not be verified."

  defp with_domain(conn, name, id, fun) do
    with_organization(conn, name, fn organization ->
      case OrganizationDomains.get(organization, safe_to_integer(id) || 0) do
        nil -> not_found(conn)
        domain -> fun.(organization, domain)
      end
    end)
  end

  defp domain_error(%Ecto.Changeset{} = changeset) do
    case translate_errors(changeset)[:domain] do
      nil -> "The domain could not be added."
      message -> "Domain #{message}."
    end
  end

  defp with_organization(conn, name, fun) do
    user = conn.assigns.current_user
    organization = Organizations.get(name)

    cond do
      is_nil(organization) ->
        not_found(conn)

      not SSO.reachable?(organization) ->
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

  # Every configuration action lands back on the SSO tab, saying what changed or
  # why it did not. `success` is the message, or a function of what came back
  # when the message names it.
  defp redirect_result(conn, organization, result, success, error) do
    case result do
      {:ok, value} ->
        redirect_with_flash(conn, organization, :info, success_message(success, value))

      {:error, reason} ->
        redirect_with_flash(conn, organization, :error, error.(reason))
    end
  end

  defp success_message(message, _value) when is_binary(message), do: message
  defp success_message(fun, value) when is_function(fun, 1), do: fun.(value)

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

  defp delete_error(:connection_enabled),
    do: "Disable SSO login before removing the configuration."

  defp delete_error(:not_configured), do: "There is no SSO configuration to remove."
  defp delete_error(reason), do: configuration_error(reason)

  defp rotation_error(:rotation_not_ready),
    do: "Test the replacement secret before completing rotation."

  defp rotation_error(%Ecto.Changeset{}), do: "Enter a valid replacement client secret."
  defp rotation_error(reason), do: configuration_error(reason)
end
