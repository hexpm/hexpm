defmodule Hexpm.CDN.Fastly do
  alias Hexpm.HTTP

  @behaviour Hexpm.CDN
  @fastly_url "https://api.fastly.com/"

  def purge_key(service, keys) do
    keys = keys |> List.wrap() |> Enum.uniq()
    body = %{"surrogate_keys" => keys}
    service_id = Application.get_env(:hexpm, service)

    {:ok, 200, _, _} = post("service/#{service_id}/purge", body)

    Task.Supervisor.start_child(Hexpm.Tasks, fn ->
      Process.sleep(2000)
      {:ok, 200, _, _} = post("service/#{service_id}/purge", body)
      Process.sleep(2000)
      {:ok, 200, _, _} = post("service/#{service_id}/purge", body)
    end)

    :ok
  end

  def public_ips() do
    {:ok, 200, _, body} = get("public-ip-list")
    Enum.map(body["addresses"], &Hexpm.Utils.parse_ip_mask/1)
  end

  defp auth() do
    Application.get_env(:hexpm, :fastly_key)
  end

  defp post(url, body) do
    url = @fastly_url <> url

    headers = [
      {"fastly-key", auth()},
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]

    body = Jason.encode!(body)

    fn -> HTTP.post(url, headers, body) end
    |> HTTP.retry("fastly")
    |> read_body()
  end

  defp get(url) do
    url = @fastly_url <> url
    headers = [{"fastly-key", auth()}, {"accept", "application/json"}]

    fn -> HTTP.get(url, headers) end
    |> HTTP.retry("fastly")
    |> read_body()
  end

  defp read_body({:ok, status, headers, body}) do
    body =
      case Jason.decode(body) do
        {:ok, map} -> map
        {:error, _} -> body
      end

    {:ok, status, headers, body}
  end
end
