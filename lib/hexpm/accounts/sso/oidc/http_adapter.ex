defmodule Hexpm.Accounts.SSO.OIDC.HTTPAdapter do
  @behaviour :oidcc_http_adapter

  alias Hexpm.Accounts.SSO.SafeURL

  @max_response_bytes 1_000_000

  # oidcc runs the adapter inline in the calling process, so a per-call context
  # in the process dictionary carries the raw response back out: oidcc hands
  # back decoded records and hexpm persists the documents as they arrived.
  def open do
    ref = make_ref()
    Process.put(ref, %{})
    ref
  end

  def close(ref), do: Process.delete(ref)

  def get(ref, key), do: Map.get(context(ref), key)

  def put(ref, key, value), do: Process.put(ref, Map.put(context(ref), key, value))

  def request_opts(ref, timeout) do
    %{timeout: timeout, http_adapter: {__MODULE__, %{ref: ref}}}
  end

  def reraise_client_exception!(ref) do
    case get(ref, :exception) do
      nil -> :ok
      {exception, stacktrace} -> reraise(exception, stacktrace)
    end
  end

  @impl :oidcc_http_adapter
  def request(method, request, http_options, _request_options, %{ref: ref}) do
    guard(ref, fn -> send_request(method, request, http_options, ref) end)
  end

  # Everything below the adapter boundary is ours, so its exceptions stay ours:
  # they are held here and re-raised at the SSO boundary rather than reaching
  # oidcc, whose callback contract is an ok or error tuple.
  defp guard(ref, fun) do
    fun.()
  rescue
    exception ->
      put(ref, :exception, {exception, __STACKTRACE__})
      {:error, :client_exception}
  end

  defp send_request(method, request, http_options, ref) do
    url = request_url(request)
    timeout = timeout(http_options)

    with {:ok, uri, addresses} <- SafeURL.resolve(url) do
      opts = [
        decode_body: false,
        connect_address: List.first(addresses),
        connect_hostname: uri.host,
        max_body_bytes: @max_response_bytes,
        receive_timeout: timeout,
        request_timeout: timeout
      ]

      method
      |> dispatch(url, request, opts)
      |> handle_response(ref)
    end
  end

  defp dispatch(:get, url, request, opts) do
    Hexpm.HTTP.impl().get(url, request_headers(request), opts)
  end

  defp dispatch(:post, url, request, opts) do
    Hexpm.HTTP.impl().post(url, request_headers(request), request_body(request), opts)
  end

  defp handle_response({:ok, status, headers, body}, ref) do
    put(ref, :response, %{headers: headers, body: body})
    {:ok, {{~c"HTTP/1.1", status, ~c""}, response_headers(headers), body}}
  end

  defp handle_response({:error, reason}, _ref), do: {:error, {:transport, reason}}

  defp context(ref), do: Process.get(ref) || %{}

  defp timeout(http_options), do: Keyword.get(http_options, :timeout, 5_000)

  defp request_url({url, _headers}), do: to_url(url)
  defp request_url({url, _headers, _content_type, _body}), do: to_url(url)

  defp to_url(url) when is_binary(url), do: url
  defp to_url(url) when is_list(url), do: IO.iodata_to_binary(url)

  defp request_headers({_url, headers}) do
    headers |> normalize_headers() |> put_new_header("accept", "application/json")
  end

  defp request_headers({_url, headers, content_type, _body}) do
    headers
    |> normalize_headers()
    |> put_new_header("accept", "application/json")
    |> put_new_header("content-type", to_string(content_type))
  end

  defp request_body({_url, _headers, _content_type, body}), do: IO.iodata_to_binary(body)

  defp normalize_headers(headers) do
    Enum.map(headers, fn {name, value} ->
      {name |> to_string() |> String.downcase(), IO.iodata_to_binary(value)}
    end)
  end

  defp put_new_header(headers, name, value) do
    if List.keymember?(headers, name, 0), do: headers, else: headers ++ [{name, value}]
  end

  # oidcc reads response headers with proplists:lookup/2, which only matches
  # charlist names.
  defp response_headers(headers) do
    Enum.map(headers, fn {name, value} ->
      {name |> to_string() |> String.downcase() |> String.to_charlist(), value}
    end)
  end
end
