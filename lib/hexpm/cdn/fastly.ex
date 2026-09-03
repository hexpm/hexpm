defmodule Hexpm.CDN.Fastly do
  @moduledoc """
  Fastly purging and post-purge verification.

  `verify/2` fetches every target the way a client would and compares the
  write number the edge serves (`x-cache-write`, the object's `write`
  metadata) with the target's: a copy at or past it is current, since a
  later write of the object only raises the number, so a check that runs
  after the next write of the same object still passes. Copies cached before
  writes were numbered carry no number and are compared by ETag. The checks
  of all targets and POPs run in one task stream, so `@verify_concurrency`
  bounds the requests in flight for the whole batch. Fastly routes by
  anycast, so a plain request cannot pick its POP; the workers run in
  us-east4, next to the IAD shield every other POP fetches through, so the
  direct fetch checks the shield, which is where the purges of August 2026
  went missing. For the repository service the check also asks the POPs in
  `:fastly_probe_pops`, one per continent: the Compute code accepts
  `hex-cache-probe: <shield code>` with a valid `fastly-key` and answers
  from that POP's cache, tunnelled over Fastly's shield network. The CDN
  turns the HEAD into a GET on a miss, so a probe also pulls the object into
  that POP's cache, which a client there would have done anyway. Every
  answer carries `x-cache-served-by`, `x-cache`, `x-cache-age` and
  `x-cache-hits` (shield first, then edge), so a stale result names the
  caches that kept the old copy and how long they had it. A probe that fails
  to answer is reported in telemetry and the log but does not fail the
  check; a stale answer from any POP does.

  Objects in a private repository are fetched with a token minted for the
  check: two minutes, scoped to that repository, verified by the edge
  against the JWT public key it holds and useless against the API, which
  only accepts tokens it has on record.
  """

  alias Hexpm.HTTP

  require Logger

  @behaviour Hexpm.CDN
  @fastly_url "https://api.fastly.com/"
  @retry_opts [attempts: 5, base_delay: 200, statuses: [429, 500..599]]
  @probe_timeout 15_000
  @verify_concurrency 10
  @cache_headers ~w(x-cache-served-by x-cache x-cache-age x-cache-hits)

  @impl true
  def purge_key(service, keys) do
    service_id = Application.get_env(:hexpm, service)
    body = %{"surrogate_keys" => keys}
    metadata = %{service: service, keys: keys}

    :telemetry.span([:hexpm, :cdn, :purge_request], metadata, fn ->
      case post(service, "service/#{service_id}/purge", body) do
        {:ok, 200, _headers, body} ->
          Logger.info(%{
            message: "CDN purge requested",
            event: "cdn.purge_request",
            service: service,
            keys: keys,
            status: 200,
            purge_ids: inspect(body)
          })

          {:ok, Map.put(metadata, :status, 200)}

        {:ok, status, _headers, body} ->
          Logger.error(%{
            message: "CDN purge request failed",
            event: "cdn.purge_request",
            service: service,
            keys: keys,
            status: status,
            error: inspect(body)
          })

          {{:error, {:status, status, body}}, Map.put(metadata, :status, status)}

        {:error, reason} ->
          Logger.error(%{
            message: "CDN purge request failed",
            event: "cdn.purge_request",
            service: service,
            keys: keys,
            error: inspect(reason)
          })

          {{:error, reason}, Map.put(metadata, :status, :error)}
      end
    end)
  end

  @impl true
  def verify(service, targets) do
    checks =
      for target <- targets,
          {pop, headers} <- [{:nearest, target_headers(target)} | probes(service, target)],
          do: {target, pop, headers}

    checks
    |> Task.async_stream(
      fn {target, pop, headers} -> {target, pop, check(target, pop, headers)} end,
      max_concurrency: @verify_concurrency,
      timeout: @probe_timeout + 5_000,
      on_timeout: :kill_task,
      ordered: false,
      zip_input_on_exit: true
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, {{target, pop, _headers}, reason}} -> {target, pop, {:error, {:exit, reason}}}
    end)
    |> Enum.group_by(fn {target, _pop, _result} -> target end)
    |> Enum.map(fn {target, results} -> {target, verdict(results)} end)
  end

  # Any POP serving the old object makes the target stale; otherwise the
  # nearest fetch decides, since a failed probe is no evidence of staleness.
  defp verdict(results) do
    stale =
      for {_target, pop, {:error, {:stale, served, cache}}} <- results,
          do: %{pop: pop, served: served, cache: cache}

    stale =
      Enum.sort_by(stale, fn
        %{pop: :nearest} -> {0, ""}
        %{pop: pop} -> {1, pop}
      end)

    if stale == [] do
      [nearest] = for {_target, :nearest, result} <- results, do: result
      nearest
    else
      {:error, {:stale, stale}}
    end
  end

  defp target_headers(target) do
    case Map.get(target, :repository) do
      nil -> []
      repository -> [{"authorization", "Bearer " <> repository_token(repository)}]
    end
  end

  defp probes(:fastly_hexrepo, target) do
    key = Application.get_env(:hexpm, :fastly_key)

    for pop <- Application.fetch_env!(:hexpm, :fastly_probe_pops) do
      {pop, [{"hex-cache-probe", pop}, {"fastly-key", key} | target_headers(target)]}
    end
  end

  defp probes(_service, _target), do: []

  defp check(%{url: url} = target, pop, headers) do
    :telemetry.span([:hexpm, :cdn, :verify], %{url: url, pop: pop}, fn ->
      result =
        case HTTP.impl().head(url, headers, decode_body: false, request_timeout: @probe_timeout) do
          {:ok, status, headers, _body} -> compare(target, status, headers)
          {:error, reason} -> {:error, reason}
        end

      if pop != :nearest and verify_result(result) == :error do
        Logger.warning(%{
          message: "CDN probe failed",
          event: "cdn.probe",
          pop: pop,
          url: url,
          result: inspect(result)
        })
      end

      {result, %{url: url, pop: pop, result: verify_result(result)}}
    end)
  end

  defp repository_token(repository) do
    {:ok, token, _jti} =
      Hexpm.OAuth.JWT.generate_access_token("cdn-verify", "system", ["repository:#{repository}"],
        expires_in: 120
      )

    token
  end

  # A target without a number was written before writes were numbered, so
  # any numbered copy is a later write.
  defp compare(%{etag: etag} = target, 200, headers) when is_binary(etag) do
    case {target[:write], served_write(headers)} do
      {write, served} when is_integer(write) and is_integer(served) ->
        if served >= write, do: :ok, else: {:error, {:stale, {:write, served}, cache(headers)}}

      {nil, served} when is_integer(served) ->
        :ok

      _ ->
        served = header(headers, "etag")

        if normalize_etag(served) == normalize_etag(etag),
          do: :ok,
          else: {:error, {:stale, {:etag, served}, cache(headers)}}
    end
  end

  defp compare(%{etag: nil}, 404, _headers), do: :ok

  # A deleted object answered with a copy written after the deletion has
  # been re-created since; anything else is the copy the deletion should
  # have removed.
  defp compare(%{etag: nil} = target, 200, headers) do
    served = served_write(headers)

    cond do
      not is_integer(served) -> {:error, {:stale, {:write, served}, cache(headers)}}
      is_nil(target[:write]) -> :ok
      served > target[:write] -> :ok
      true -> {:error, {:stale, {:write, served}, cache(headers)}}
    end
  end

  # A page removed from a subdomain that names an organization is redirected
  # to the organization's docs host instead of answering 404.
  defp compare(%{etag: nil, url: url}, 301, headers) do
    if header(headers, "location") == organization_docs_url(url) do
      :ok
    else
      {:error, {:status, 301, cache(headers)}}
    end
  end

  defp compare(_target, status, headers), do: {:error, {:status, status, cache(headers)}}

  defp served_write(headers) do
    case header(headers, "x-cache-write") do
      nil -> nil
      value -> with {write, ""} <- Integer.parse(value), do: write, else: (_ -> nil)
    end
  end

  defp organization_docs_url(url) do
    target = URI.parse(url)
    [subdomain | _] = String.split(target.host, ".")
    docs = URI.parse(Application.fetch_env!(:hexpm, :private_docs_url))
    URI.to_string(%{docs | host: "#{subdomain}.#{docs.host}", path: target.path})
  end

  defp cache(headers) do
    case for(name <- @cache_headers, value = header(headers, name), do: "#{name}: #{value}") do
      [] -> nil
      pairs -> Enum.join(pairs, "; ")
    end
  end

  @impl true
  def public_ips() do
    {:ok, 200, _, body} = get("public-ip-list")
    Enum.map(body["addresses"], &Hexpm.Utils.parse_ip_mask/1)
  end

  defp verify_result(:ok), do: :ok
  defp verify_result({:error, {:stale, _served, _served_by}}), do: :stale
  defp verify_result({:error, _}), do: :error

  defp header(headers, name) do
    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(key) == name, do: value
    end)
  end

  defp normalize_etag(nil), do: nil

  defp normalize_etag(etag) do
    etag
    |> String.trim()
    |> String.replace_prefix("W/", "")
    |> String.trim("\"")
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

    HTTP.retry(fn -> HTTP.impl().post(url, headers, body) end, "fastly", @retry_opts)
  end

  defp get(url) do
    headers = [{"fastly-key", auth(:fastly_hexrepo)}, {"accept", "application/json"}]

    fn -> HTTP.impl().get(@fastly_url <> url, headers) end
    |> HTTP.retry("fastly", @retry_opts)
  end
end
