defmodule Hexpm.CDN.Fastly do
  require Logger

  @behaviour Hexpm.CDN
  @fastly_url "https://api.fastly.com/"
  @retry_times 10

  def purge_key(service, keys) do
    keys = keys |> List.wrap() |> Enum.uniq()
    body = %{"surrogate_keys" => keys}
    service_id = Application.get_env(:hexpm, service)

    {:ok, 200, _, _} = post("service/#{service_id}/purge", body)
    :ok
  end

  def public_ips() do
    {:ok, 200, _, body} = get("public-ip-list")

    Enum.map(body["addresses"], fn range ->
      [ip, mask] = String.split(range, "/")
      {Hexpm.Utils.parse_ip(ip), String.to_integer(mask)}
    end)
  end

  defp auth() do
    Application.get_env(:hexpm, :fastly_key)
  end

  defp post(url, body) do
    url = @fastly_url <> url

    headers = [
      "fastly-key": auth(),
      accept: "application/json",
      "content-type": "application/json"
    ]

    body = Hexpm.Web.Jiffy.encode!(body)

    retry(fn -> :hackney.post(url, headers, body, []) end, @retry_times)
    |> read_body()
  end

  defp get(url) do
    url = @fastly_url <> url
    headers = ["fastly-key": auth(), accept: "application/json"]

    retry(fn -> :hackney.get(url, headers, []) end, @retry_times)
    |> read_body()
  end

  defp retry(fun, times) do
    case fun.() do
      {:error, reason} ->
        Logger.warn("Fastly API ERROR: #{inspect(reason)}")

        if times > 0 do
          retry(fun, times - 1)
        else
          {:error, reason}
        end

      result ->
        result
    end
  end

  defp read_body({:ok, status, headers, client}) do
    {:ok, body} = :hackney.body(client)

    body =
      case Hexpm.Web.Jiffy.decode(body) do
        {:ok, map} -> map
        {:error, _} -> body
      end

    {:ok, status, headers, body}
  end
end
