defmodule HexWeb.CDN.Fastly do
  @behaviour HexWeb.CDN
  @fastly_url "https://api.fastly.com/"

  def purge_key(service, key) do
    service_id = Application.get_env(:hex_web, service)
    {:ok, 200, _, %{"status" => "ok"}} = post("service/#{service_id}/key/#{key}", %{})
    :ok
  end

  defp auth() do
    Application.get_env(:hex_web, :fastly_key)
  end

  defp post(url, body) do
    url = @fastly_url <> url
    headers = [
      "fastly-key": auth(),
      "accept": "application/json",
      "content-type": "application/json"]

    body = Poison.encode!(body)
    :hackney.post(url, headers, body, [])
    |> read_body
  end

  defp read_body({:ok, status, headers, client}) do
    {:ok, body} = :hackney.body(client)
    map = Poison.decode!(body)
    {:ok, status, headers, map}
  end
end
