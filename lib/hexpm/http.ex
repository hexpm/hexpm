defmodule Hexpm.HTTP.Interface do
  @type url() :: String.t() | URI.t()
  @type headers() :: Mint.Types.headers()
  @type params() :: iodata() | map()
  @type opts() :: Keyword.t()
  @type response() ::
          {:ok, Mint.Types.status(), Mint.Types.headers(), binary()} | {:error, Exception.t()}

  @callback get(url(), headers()) :: response()
  @callback get(url(), headers(), opts()) :: response()
  @callback post(url(), headers(), params()) :: response()
  @callback post(url(), headers(), params(), opts()) :: response()
  @callback put(url(), headers(), params()) :: response()
  @callback put(url(), headers(), params(), opts()) :: response()
  @callback put_file(url(), headers(), Path.t(), opts()) :: response()
  @callback patch(url(), headers(), params()) :: response()
  @callback patch(url(), headers(), params(), opts()) :: response()
  @callback delete(url(), headers()) :: response()
  @callback delete(url(), headers(), opts()) :: response()
end

defmodule Hexpm.HTTP do
  require Logger

  @behaviour Hexpm.HTTP.Interface
  @default_attempts 3
  @default_base_delay 100
  @request_opts [:pool_timeout, :receive_timeout, :request_timeout]

  def impl() do
    Application.get_env(:hexpm, :http_impl, __MODULE__)
  end

  @impl Hexpm.HTTP.Interface
  def get(url, headers, opts \\ []), do: do_request(:get, url, headers, nil, opts)

  @impl Hexpm.HTTP.Interface
  def post(url, headers, body, opts \\ []), do: do_request(:post, url, headers, body, opts)

  @impl Hexpm.HTTP.Interface
  def put(url, headers, body, opts \\ []), do: do_request(:put, url, headers, body, opts)

  @impl Hexpm.HTTP.Interface
  def put_file(url, headers, path, opts \\ []) do
    do_request(:put, url, headers, {:stream, File.stream!(path, 65_536)}, opts)
  end

  @impl Hexpm.HTTP.Interface
  def patch(url, headers, body, opts \\ []), do: do_request(:patch, url, headers, body, opts)

  @impl Hexpm.HTTP.Interface
  def delete(url, headers, opts \\ []), do: do_request(:delete, url, headers, nil, opts)

  defp do_request(method, url, headers, body, opts) do
    {request_opts, build_opts} = Keyword.split(opts, @request_opts)
    params = encode_params(body, headers)

    method
    |> Finch.build(url, headers, params, build_opts)
    |> Finch.request(Hexpm.Finch, request_opts)
    |> read_response()
  end

  defp encode_params(body, _headers) when is_binary(body) or is_nil(body) do
    body
  end

  defp encode_params({:stream, _enumerable} = body, _headers), do: body

  defp encode_params(body, _headers) when is_list(body), do: body

  defp encode_params(body, headers) when is_map(body) do
    case List.keyfind(headers, "content-type", 0) do
      {_, "application/x-www-form-urlencoded"} -> URI.encode_query(body)
      {_, "application/json"} -> Jason.encode!(body)
      nil -> body
    end
  end

  defp decode_body(body, headers) do
    case List.keyfind(headers, "content-type", 0) do
      {_, "application/json" <> _} -> Jason.decode!(body)
      _ -> body
    end
  end

  defp read_response({:ok, %Finch.Response{status: status, headers: headers, body: body}}) do
    params = decode_body(body, headers)
    {:ok, status, headers, params}
  end

  defp read_response({:error, reason}) do
    {:error, reason}
  end

  def retry(fun, name, opts \\ []) do
    attempts = Keyword.get(opts, :attempts, Keyword.get(opts, :max_attempts, @default_attempts))
    base_delay = Keyword.get(opts, :base_delay, @default_base_delay)
    statuses = Keyword.get(opts, :statuses, Keyword.get(opts, :retryable_statuses, []))
    retry(fun, name, attempts, base_delay, statuses, 0)
  end

  defp retry(fun, name, attempts, base_delay, statuses, times) do
    case fun.() do
      {:ok, status, _headers, _body} = result ->
        if retryable_status?(status, statuses) do
          do_retry(fun, name, attempts, base_delay, statuses, times, "status #{status}")
        else
          result
        end

      {:error, reason} ->
        do_retry(fun, name, attempts, base_delay, statuses, times, reason)

      result ->
        result
    end
  end

  defp do_retry(fun, name, attempts, base_delay, statuses, times, reason) do
    Logger.warning("#{name} API ERROR: #{inspect(reason)}")

    if times + 1 < attempts do
      sleep = trunc(:math.pow(3, times) * base_delay)
      if sleep > 0, do: Process.sleep(sleep)
      retry(fun, name, attempts, base_delay, statuses, times + 1)
    else
      {:error, reason}
    end
  end

  defp retryable_status?(status, statuses) do
    Enum.any?(statuses, fn
      %Range{} = range -> status in range
      expected -> status == expected
    end)
  end
end
