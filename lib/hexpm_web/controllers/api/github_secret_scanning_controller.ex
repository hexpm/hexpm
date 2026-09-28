defmodule HexpmWeb.API.GitHubSecretScanningController do
  use HexpmWeb, :controller

  require Logger

  alias Hexpm.GitHub.SecretScanning

  @doc """
  Receives secret alert payloads from GitHub's secret scanning partner program.

  GitHub POSTs here whenever it detects a `hex_`-prefixed API key in a public
  repository or npm package. We verify the ECDSA-P256-SHA256 signature using
  GitHub's published public keys, then immediately revoke any matched keys and
  notify affected users by email.

  No authentication is used — GitHub identifies itself via the signature.
  Returns 200 on success (including when tokens are not found), 400 on
  malformed payload, and 403 on signature verification failure.
  """
  def create(conn, _params) do
    raw_body = conn.assigns[:raw_body] || ""
    key_id = get_req_header(conn, "github-public-key-identifier") |> List.first("")
    signature = get_req_header(conn, "github-public-key-signature") |> List.first("")

    cond do
      raw_body == "" ->
        render_error(conn, 400, message: "missing body")

      SecretScanning.verify_signature(raw_body, key_id, signature) ->
        case Jason.decode(raw_body) do
          {:ok, alerts} when is_list(alerts) ->
            results = SecretScanning.process_alerts(alerts)
            revoked = Enum.count(results, &(&1["label"] == "true_positive"))

            Logger.info("GitHub secret scanning: revoked=#{revoked} alerts=#{length(alerts)}")

            json(conn, results)

          _ ->
            render_error(conn, 400, message: "body must be a JSON array")
        end

      true ->
        Logger.warning(
          "GitHub secret scanning: invalid signature from #{inspect(conn.remote_ip)}"
        )

        render_error(conn, 403, message: "invalid signature")
    end
  end
end
