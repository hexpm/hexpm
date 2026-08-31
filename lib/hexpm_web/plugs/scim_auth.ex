defmodule HexpmWeb.Plugs.SCIMAuth do
  @moduledoc """
  Authenticates the provisioning surface with the connection's SCIM bearer
  token.

  The token addresses one connection, so resolving it decides the organization
  too; nothing on this surface takes a path that names one. Refusals carry the
  SCIM error schema, and an organization outside the SSO gate refuses the same
  way as a wrong token, since its own token stopping working is not worth
  distinguishing from revocation.
  """

  import Plug.Conn
  import HexpmWeb.SCIMHelpers

  alias Hexpm.Accounts.SSO

  def init(opts), do: opts

  def call(conn, _opts) do
    if SSO.available?() do
      authenticate(conn)
    else
      scim_error(conn, 404, "Not found")
    end
  end

  defp authenticate(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, connection} <- SSO.scim_auth(token) do
      conn
      |> assign(:scim_connection, connection)
      |> assign(:organization, connection.organization)
    else
      _refused ->
        conn
        |> put_resp_header("www-authenticate", ~s(Bearer realm="hexpm-scim"))
        |> scim_error(401, "Authentication failed")
    end
  end
end
