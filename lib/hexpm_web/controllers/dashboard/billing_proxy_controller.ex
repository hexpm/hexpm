defmodule HexpmWeb.Dashboard.BillingProxyController do
  use HexpmWeb, :controller

  plug :requires_login

  @timeout 15_000

  @allowed_actions ~w(setup_intent confirm_setup_intent)

  def proxy(conn, %{"path" => ["api", "customers", organization, action] = path})
      when action in @allowed_actions do
    access_organization(conn, organization, "admin", fn _organization ->
      billing_url = Application.get_env(:hexpm, :billing_url)
      billing_key = Application.get_env(:hexpm, :billing_key)
      url = billing_url <> "/" <> Enum.join(path, "/")

      body = Jason.encode!(conn.body_params)

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
          |> send_resp(502, Jason.encode!(%{"errors" => inspect(reason)}))
      end
    end)
  end

  def proxy(conn, _params) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{"errors" => "Not found"}))
  end

  defp encode_body(body) when is_binary(body), do: body
  defp encode_body(body), do: Jason.encode!(body)

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
        |> send_resp(403, Jason.encode!(%{"errors" => "Forbidden"}))
      end
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(404, Jason.encode!(%{"errors" => "Not found"}))
    end
  end
end
