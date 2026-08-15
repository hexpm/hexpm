defmodule Hexpm.CDN.Fastly do
  alias Hexpm.HTTP

  @behaviour Hexpm.CDN
  @fastly_url "https://api.fastly.com/"
  @fastly_purge_wait 4000

  def purge_key(service, keys) do
    keys = keys |> List.wrap() |> Enum.uniq()
    body = %{"surrogate_keys" => keys}
    service_id = Application.get_env(:hexpm, service)
    sleep_time = div(Application.get_env(:hexpm, :fastly_purge_wait, @fastly_purge_wait), 2)

    {:ok, 200, _, _} = post(service, "service/#{service_id}/purge", body)

    Task.Supervisor.start_child(Hexpm.Tasks, fn ->
      Process.sleep(sleep_time)
      {:ok, 200, _, _} = post(service, "service/#{service_id}/purge", body)
      Process.sleep(sleep_time)
      {:ok, 200, _, _} = post(service, "service/#{service_id}/purge", body)
    end)

    :ok
  end

  def public_ips() do
    {:ok, 200, _, body} = get("public-ip-list")
    Enum.map(body["addresses"], &Hexpm.Utils.parse_ip_mask/1)
  end

  defp auth(service) when service in [:fastly_hexdocs, :fastly_hexdocs_private],
    do: Application.get_env(:hexpm, :fastly_docs_key)

  defp auth(_service), do: Application.get_env(:hexpm, :fastly_key)

  defp post(service, url, body) do
    url = @fastly_url <> url

    headers = [
      {"fastly-key", auth(service)},
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]

    opts =
      if service in [:fastly_hexdocs, :fastly_hexdocs_private] do
        [attempts: 5, base_delay: 200, statuses: [429, 500..599]]
      else
        []
      end

    HTTP.retry(fn -> HTTP.impl().post(url, headers, body) end, "fastly", opts)
  end

  defp get(url) do
    url = @fastly_url <> url
    headers = [{"fastly-key", auth(:fastly_hexrepo)}, {"accept", "application/json"}]

    fn -> HTTP.impl().get(url, headers) end
    |> HTTP.retry("fastly")
  end
end
