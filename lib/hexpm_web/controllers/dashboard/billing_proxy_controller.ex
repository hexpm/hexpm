defmodule HexpmWeb.Dashboard.BillingProxyController do
  use HexpmWeb, :controller

  plug :requires_login

  # Changing the organization's billing setup takes sudo on the screen this
  # forwards from, and it forwards with the server's own billing credential, so
  # it takes sudo here too. Ahead of the SSO plug, so a session sent off to
  # reauthenticate never counts as having reached billing.
  plug HexpmWeb.Plugs.Sudo

  # The browser's billing forms talk to the billing service through here, so it
  # is the billing carve-out under another address and is accounted for as one.
  plug HexpmWeb.Plugs.OrganizationSSO,
    organization: :billing_proxy,
    except: [:proxy],
    screen: :billing

  @timeout 15_000

  @allowed_actions ~w(setup_intent confirm_setup_intent)

  def proxy(conn, %{"path" => ["api", "customers", organization, action] = path})
      when action in @allowed_actions do
    access_organization(conn, organization, "admin", fn _organization ->
      billing_url = Application.get_env(:hexpm, :billing_url)
      billing_key = Application.get_env(:hexpm, :billing_key)
      url = billing_url <> "/" <> Enum.join(path, "/")

      body = JSON.encode!(conn.body_params)

      headers = [
        {"authorization", billing_key},
        {"content-type", "application/json"},
        {"accept", "application/json"}
      ]

      case Hexpm.HTTP.impl().post(url, headers, body, receive_timeout: @timeout) do
        {:ok, status, _headers, response_body} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(status, encode_body(response_body))

        {:error, reason} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(502, JSON.encode!(%{"errors" => inspect(reason)}))
      end
    end)
  end

  def proxy(conn, _params) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, JSON.encode!(%{"errors" => "Not found"}))
  end

  defp encode_body(body) when is_binary(body), do: body
  defp encode_body(body), do: JSON.encode!(body)

  defp access_organization(conn, organization, role, fun) do
    user = conn.assigns.current_user

    organization =
      Hexpm.Accounts.Organizations.get(organization, [:user, :organization_users])

    if organization do
      repo_user = Enum.find(organization.organization_users, &(&1.user_id == user.id))

      if repo_user && repo_user.role in Hexpm.Accounts.Organization.role_or_higher(role) do
        fun.(organization)
      else
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(403, JSON.encode!(%{"errors" => "Forbidden"}))
      end
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(404, JSON.encode!(%{"errors" => "Not found"}))
    end
  end
end
