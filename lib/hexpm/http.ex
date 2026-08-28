defmodule Hexpm.HTTP.Interface do
  @type url() :: String.t() | URI.t()
  @type headers() :: Mint.Types.headers()
  @type params() :: binary() | map()
  @type opts() :: Keyword.t()
  @type response() ::
          {:ok, Mint.Types.status(), Mint.Types.headers(), binary()} | {:error, Exception.t()}

  @callback get(url(), headers()) :: response()
  @callback get(url(), headers(), opts()) :: response()
  @callback post(url(), headers(), params()) :: response()
  @callback post(url(), headers(), params(), opts()) :: response()
  @callback put(url(), headers(), params()) :: response()
  @callback put(url(), headers(), params(), opts()) :: response()
  @callback patch(url(), headers(), params()) :: response()
  @callback patch(url(), headers(), params(), opts()) :: response()
  @callback delete(url(), headers()) :: response()
  @callback delete(url(), headers(), opts()) :: response()
end

defmodule Hexpm.HTTP do
  require Logger

  @behaviour Hexpm.HTTP.Interface
  @max_retry_times 3
  @base_sleep_time 100

  def impl() do
    Application.get_env(:hexpm, :http_impl, __MODULE__)
  end

  @impl Hexpm.HTTP.Interface
  def get(url, headers, opts \\ []) do
    case Keyword.pop(opts, :max_body_size) do
      {nil, opts} ->
        build_request(:get, url, headers, nil, opts)
        |> Finch.request(Hexpm.Finch)
        |> read_response()

      {max_body_size, opts} ->
        build_request(:get, url, headers, nil, opts)
        |> stream_get(max_body_size)
    end
  end

  @impl Hexpm.HTTP.Interface
  def post(url, headers, body, opts \\ []) do
    build_request(:post, url, headers, body, opts)
    |> Finch.request(Hexpm.Finch)
    |> read_response()
  end

  @impl Hexpm.HTTP.Interface
  def put(url, headers, body, opts \\ []) do
    build_request(:put, url, headers, body, opts)
    |> Finch.request(Hexpm.Finch)
    |> read_response()
  end

  @impl Hexpm.HTTP.Interface
  def patch(url, headers, body, opts \\ []) do
    build_request(:patch, url, headers, body, opts)
    |> Finch.request(Hexpm.Finch)
    |> read_response()
  end

  @impl Hexpm.HTTP.Interface
  def delete(url, headers, opts \\ []) do
    build_request(:delete, url, headers, nil, opts)
    |> Finch.request(Hexpm.Finch)
    |> read_response()
  end

  defp build_request(method, url, headers, body, opts) do
    params = encode_params(body, headers)
    Finch.build(method, url, headers, params, opts)
  end

  # Streams the response body, aborting as soon as more than `max_body_size`
  # bytes have been received, without buffering the rest. Also rejects early
  # if the response declares a content-length larger than the limit.
  defp stream_get(request, max_body_size) do
    acc = %{status: nil, headers: [], body: [], size: 0, too_large: false}

    fun = fn
      {:status, value}, acc ->
        {:cont, %{acc | status: value}}

      {:headers, value}, acc ->
        headers = acc.headers ++ value

        if content_length_too_large?(headers, max_body_size) do
          {:halt, %{acc | headers: headers, too_large: true}}
        else
          {:cont, %{acc | headers: headers}}
        end

      {:data, value}, acc ->
        size = acc.size + byte_size(value)

        if size > max_body_size do
          {:halt, %{acc | size: size, too_large: true}}
        else
          {:cont, %{acc | body: [acc.body, value], size: size}}
        end

      {:trailers, _value}, acc ->
        {:cont, acc}
    end

    case Finch.stream_while(request, Hexpm.Finch, acc, fun) do
      {:ok, %{too_large: true}} ->
        {:error, :body_too_large}

      {:ok, %{status: status, headers: headers, body: body}} ->
        params = decode_body(IO.iodata_to_binary(body), headers)
        {:ok, status, headers, params}

      {:error, reason, _acc} ->
        {:error, reason}
    end
  end

  defp content_length_too_large?(headers, max_body_size) do
    case List.keyfind(headers, "content-length", 0) do
      {_, value} ->
        case Integer.parse(value) do
          {length, _} -> length > max_body_size
          :error -> false
        end

      nil ->
        false
    end
  end

  defp encode_params(body, _headers) when is_binary(body) or is_nil(body) do
    body
  end

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

  def retry(fun, name) do
    retry(fun, name, 0)
  end

  defp retry(fun, name, times) do
    case fun.() do
      {:error, reason} ->
        Logger.warning("#{name} API ERROR: #{inspect(reason)}")

        if times + 1 < @max_retry_times do
          sleep = trunc(:math.pow(3, times) * @base_sleep_time)
          :timer.sleep(sleep)
          retry(fun, name, times + 1)
        else
          {:error, reason}
        end

      result ->
        result
    end
  end
end
