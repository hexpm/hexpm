defmodule HexWeb.CDN.Fastly do
  @behaviour HexWeb.CDN
  @fastly_url "https://api.fastly.com/"

  def purge_key(service, key) do
    service_id = Application.get_env(:hex_web, service)
    case post("service/#{service_id}/purge/#{key}", %{}) do
      {:ok, status, _, _} when status in [200, 404] ->
        :ok
    end
  end

  def public_ips do
    {:ok, 200, _, body} = get("public-ip-list")
    Enum.map(body["addresses"], fn range ->
      [ip, mask] = String.split(range, "/")
      {HexWeb.Utils.parse_ip(ip), String.to_integer(mask)}
    end)
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

  defp get(url) do
    url = @fastly_url <> url
    headers = [
      "fastly-key": auth(),
      "accept": "application/json"]

    :hackney.get(url, headers, [])
    |> read_body
  end

  defp read_body({:ok, status, headers, client}) do
    {:ok, body} = :hackney.body(client)
    body = case Poison.decode(body) do
      {:ok, map}  -> map
      {:error, _} -> body
    end
    {:ok, status, headers, body}
  end
end
