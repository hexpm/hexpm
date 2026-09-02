defmodule HexpmWeb.SCIMHelpers do
  @moduledoc """
  Response encoding for the SCIM surface.

  SCIM has its own media type and its own error schema (RFC 7644), and the
  provisioning agent is neither a person nor an organization acting through
  the API, so nothing here goes through the JSON views or `ErrorView`.
  """

  import Plug.Conn

  @error_schema "urn:ietf:params:scim:api:messages:2.0:Error"

  def scim_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/scim+json")
    |> send_resp(status, JSON.encode_to_iodata!(body))
  end

  def scim_error(conn, status, detail, scim_type \\ nil) do
    body =
      put_scim_type(
        %{
          "schemas" => [@error_schema],
          "status" => Integer.to_string(status),
          "detail" => detail
        },
        scim_type
      )

    conn
    |> scim_json(status, body)
    |> halt()
  end

  defp put_scim_type(body, nil), do: body
  defp put_scim_type(body, scim_type), do: Map.put(body, "scimType", to_string(scim_type))
end
