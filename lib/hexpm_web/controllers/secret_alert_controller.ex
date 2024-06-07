defmodule HexpmWeb.SecretAlertController do
  use HexpmWeb, :controller

  # This endpoint is used by github to notify us of secrets that have been leaked
  # Sample POST request body from GH:
  # [
  #   {
  #     "token":"NMIfyYncKcRALEXAMPLE",
  #     "type":"mycompany_api_token",
  #     "url":"https://github.com/octocat/Hello-World/blob/12345600b9cbe38a219f39a9941c9319b600c002/foo/bar.txt",
  #     "source":"content"
  #   }
  # ]

  def notify(conn, params) do
    case Jason.decode(params) do
      {:ok, secret_matches} ->
        Enum.each(secret_matches, &parse_secret_match/1)

        conn
        |> put_status(:ok)
        |> json(%{status: "ok"})

      {:error, _} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error"})
    end
  end

  defp parse_secret_match(secret_match) do
    IO.inspect(secret_match)
  end
end
