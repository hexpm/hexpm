defmodule HexpmWeb.SSOBackchannelLogoutController do
  use HexpmWeb, :controller

  # OpenID Connect Back-Channel Logout 1.0. The provider POSTs a signed logout
  # token here, server to server, when one of its sessions ends. The token is
  # the authentication: the endpoint carries no session and no secret, and
  # everything it can do is revoke organization access that the same provider
  # created. Replays are not tracked, because re-revoking revoked sessions
  # changes nothing.

  alias Hexpm.Accounts.SSO
  alias HexpmWeb.Plugs.Attack

  plug :put_no_store
  plug :require_sso_available
  plug :rate_limit

  def create(conn, %{"organization" => name} = params) do
    organization = Organizations.get(name)

    if is_nil(organization) or not SSO.reachable?(organization) do
      not_found(conn)
    else
      handle(conn, organization, params["logout_token"])
    end
  end

  defp handle(conn, organization, logout_token) when is_binary(logout_token) do
    case SSO.backchannel_logout(organization, logout_token) do
      :ok -> send_resp(conn, 200, "")
      {:error, :not_configured} -> not_found(conn)
      {:error, _error} -> send_resp(conn, 400, "")
    end
  end

  defp handle(conn, _organization, _logout_token), do: send_resp(conn, 400, "")

  defp require_sso_available(conn, _opts) do
    if SSO.available?() do
      conn
    else
      conn
      |> not_found()
      |> halt()
    end
  end

  defp rate_limit(conn, _opts) do
    case Attack.sso_backchannel_logout_ip_throttle(conn.remote_ip) do
      {:allow, _data} ->
        conn

      {:block, _data} ->
        conn
        |> send_resp(429, "")
        |> halt()
    end
  end

  defp put_no_store(conn, _opts) do
    put_resp_header(conn, "cache-control", "no-store")
  end
end
