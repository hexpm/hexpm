defmodule HexpmWeb.API.OIDCController do
  use HexpmWeb, :controller

  alias Hexpm.TrustedPublishers
  alias HexpmWeb.Plugs.Attack

  plug :feature_enabled
  plug :mint_rate_limit when action in [:mint_token]

  @doc """
  Returns the OIDC audience Hex expects for trusted publisher tokens.
  """
  def audience(conn, _params) do
    render(conn, :audience, audience: TrustedPublishers.audience())
  end

  @doc """
  Exchanges a CI OIDC token for a short-lived Hex access token scoped to one package.
  """
  def mint_token(conn, params) do
    token = safe_param(params, "token")
    repository = safe_param(params, "repository") || "hexpm"
    package = safe_param(params, "package")

    cond do
      not is_binary(token) or token == "" ->
        render_oidc_error(conn, :invalid_request, "Missing or invalid token")

      not is_binary(package) or package == "" ->
        render_oidc_error(conn, :invalid_request, "Missing or invalid package")

      true ->
        case TrustedPublishers.verify_and_mint(token,
               repository: repository,
               package: package,
               audit: audit_data(conn)
             ) do
          {:ok, access_token} ->
            render(conn, :token, token: access_token)

          {:error, :disabled} ->
            render_oidc_error(conn, :access_denied, "Trusted publishers are disabled")

          {:error, :package_not_found} ->
            render_oidc_error(conn, :access_denied, "No matching trusted publisher")

          {:error, :no_matching_publisher} ->
            render_oidc_error(conn, :access_denied, "No matching trusted publisher")

          {:error, :token_replayed} ->
            render_oidc_error(conn, :invalid_grant, "OIDC token has already been used")

          {:error, :issuer_not_allowed} ->
            render_oidc_error(conn, :invalid_grant, "OIDC issuer is not allowed")

          {:error, reason}
          when reason in [
                 :invalid_token,
                 :algorithm_rejected,
                 :signature_invalid,
                 :audience_mismatch,
                 :token_expired,
                 :token_not_yet_valid,
                 :issued_at_in_future,
                 :issuer_mismatch,
                 :jti_missing,
                 :issuer_missing
               ] ->
            render_oidc_error(conn, :invalid_grant, "Invalid OIDC token")

          {:error, _reason} ->
            render_oidc_error(conn, :server_error, "Failed to mint token")
        end
    end
  end

  defp feature_enabled(conn, _opts) do
    if TrustedPublishers.enabled?() do
      conn
    else
      conn
      |> put_status(404)
      |> render(:error, error_type: :not_found, description: "Not found")
      |> halt()
    end
  end

  defp mint_rate_limit(conn, _opts) do
    case Attack.trusted_publisher_mint_ip_throttle(conn.remote_ip) do
      {:allow, _} ->
        conn

      {:block, _} ->
        conn
        |> put_status(429)
        |> render(:error,
          error_type: :slow_down,
          description: "Too many mint requests. Please try again later."
        )
        |> halt()
    end
  end

  defp safe_param(params, key) do
    case params[key] do
      value when is_binary(value) -> String.trim(value)
      _ -> nil
    end
  end

  defp render_oidc_error(conn, error_type, description) do
    status =
      case error_type do
        :invalid_request -> 400
        :invalid_grant -> 400
        :access_denied -> 403
        :server_error -> 500
        _ -> 400
      end

    conn
    |> put_status(status)
    |> render(:error, error_type: error_type, description: description)
  end
end
