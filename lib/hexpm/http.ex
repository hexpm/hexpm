defmodule Hexpm.HTTP.Interface do
  @type url() :: String.t() | URI.t()
  @type headers() :: Mint.Types.headers()
  @type params() :: iodata() | map()
  @type opts() :: Keyword.t()
  @type response() ::
          {:ok, Mint.Types.status(), Mint.Types.headers(), binary()} | {:error, Exception.t()}

  @callback get(url(), headers()) :: response()
  @callback get(url(), headers(), opts()) :: response()
  @callback head(url(), headers()) :: response()
  @callback head(url(), headers(), opts()) :: response()
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
  def head(url, headers, opts \\ []), do: do_request(:head, url, headers, nil, opts)

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
    {decode_body?, opts} = Keyword.pop(opts, :decode_body, true)
    {max_body_bytes, opts} = Keyword.pop(opts, :max_body_bytes)
    {connect_address, opts} = Keyword.pop(opts, :connect_address)
    {connect_hostname, opts} = Keyword.pop(opts, :connect_hostname)
    {connect_cacerts, opts} = Keyword.pop(opts, :connect_cacerts)
    {request_opts, build_opts} = Keyword.split(opts, @request_opts)
    params = encode_params(body, headers)

    response =
      if connect_address do
        pinned_request(
          method,
          url,
          headers,
          params,
          connect_address,
          connect_hostname,
          connect_cacerts,
          max_body_bytes,
          request_opts
        )
      else
        request = Finch.build(method, url, headers, params, build_opts)
        request(request, max_body_bytes, request_opts)
      end

    response
    |> read_response(decode_body?)
  end

  defp pinned_request(
         method,
         url,
         headers,
         body,
         address,
         hostname,
         cacerts,
         max_body_bytes,
         request_opts
       ) do
    uri = URI.parse(to_string(url))
    timeout = pinned_timeout(request_opts)

    transport_opts =
      [timeout: timeout]
      |> maybe_put_cacerts(cacerts)

    connect_opts = [hostname: hostname || uri.host, mode: :active, transport_opts: transport_opts]

    with {:ok, scheme} <- mint_scheme(uri.scheme),
         {:ok, connection} <-
           Mint.HTTP.connect(scheme, address, uri.port || default_port(scheme), connect_opts),
         {:ok, connection, request_ref} <-
           Mint.HTTP.request(
             connection,
             method |> Atom.to_string() |> String.upcase(),
             request_path(uri),
             headers,
             body || ""
           ) do
      deadline = System.monotonic_time(:millisecond) + timeout

      connection
      |> receive_pinned_response(request_ref, max_body_bytes, deadline, %{
        status: nil,
        headers: [],
        body: [],
        body_bytes: 0
      })
      |> close_pinned_connection()
    else
      {:error, connection, reason} ->
        close_pinned_connection({:error, connection, reason})

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_put_cacerts(transport_opts, nil), do: transport_opts

  defp maybe_put_cacerts(transport_opts, cacerts),
    do: Keyword.put(transport_opts, :cacerts, cacerts)

  defp receive_pinned_response(connection, request_ref, max_body_bytes, deadline, response) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      message ->
        case Mint.HTTP.stream(connection, message) do
          {:ok, connection, messages} ->
            case reduce_pinned_messages(messages, request_ref, max_body_bytes, response) do
              {:cont, response} ->
                receive_pinned_response(
                  connection,
                  request_ref,
                  max_body_bytes,
                  deadline,
                  response
                )

              {:done, response} ->
                {:ok, connection,
                 %Finch.Response{
                   status: response.status,
                   headers: response.headers,
                   body: response.body |> Enum.reverse() |> IO.iodata_to_binary()
                 }}

              {:error, reason} ->
                {:error, connection, reason}
            end

          {:error, connection, reason, _messages} ->
            {:error, connection, reason}

          :unknown ->
            receive_pinned_response(
              connection,
              request_ref,
              max_body_bytes,
              deadline,
              response
            )
        end
    after
      remaining -> {:error, connection, :timeout}
    end
  end

  defp reduce_pinned_messages(messages, request_ref, max_body_bytes, response) do
    Enum.reduce_while(messages, {:cont, response}, fn
      {:status, ^request_ref, status}, {:cont, response} ->
        {:cont, {:cont, %{response | status: status}}}

      {:headers, ^request_ref, headers}, {:cont, response} ->
        {:cont, {:cont, %{response | headers: response.headers ++ headers}}}

      {:data, ^request_ref, data}, {:cont, response} ->
        body_bytes = response.body_bytes + byte_size(data)

        if is_integer(max_body_bytes) and body_bytes > max_body_bytes do
          {:halt, {:error, :response_too_large}}
        else
          {:cont, {:cont, %{response | body: [data | response.body], body_bytes: body_bytes}}}
        end

      {:done, ^request_ref}, {:cont, response} ->
        {:halt, {:done, response}}

      {:error, ^request_ref, reason}, {:cont, _response} ->
        {:halt, {:error, reason}}

      _message, result ->
        {:cont, result}
    end)
  end

  defp close_pinned_connection({:ok, connection, response}) do
    Mint.HTTP.close(connection)
    {:ok, response}
  end

  defp close_pinned_connection({:error, connection, reason}) do
    Mint.HTTP.close(connection)
    {:error, reason}
  end

  defp pinned_timeout(request_opts) do
    request_timeout = Keyword.get(request_opts, :request_timeout, 5_000)
    receive_timeout = Keyword.get(request_opts, :receive_timeout, request_timeout)
    min(request_timeout, receive_timeout)
  end

  defp request_path(uri) do
    path = uri.path || "/"
    if uri.query, do: path <> "?" <> uri.query, else: path
  end

  defp mint_scheme("http"), do: {:ok, :http}
  defp mint_scheme("https"), do: {:ok, :https}
  defp mint_scheme(_scheme), do: {:error, :unsupported_scheme}

  defp default_port(:http), do: 80
  defp default_port(:https), do: 443

  defp request(request, nil, request_opts) do
    Finch.request(request, Hexpm.Finch, request_opts)
  end

  defp request(request, max_body_bytes, request_opts)
       when is_integer(max_body_bytes) and max_body_bytes >= 0 do
    initial = %{status: nil, headers: [], body: [], body_bytes: 0, too_large?: false}

    stream = fn
      {:status, status}, acc ->
        {:cont, %{acc | status: status}}

      {:headers, headers}, acc ->
        {:cont, %{acc | headers: acc.headers ++ headers}}

      {:data, data}, acc ->
        body_bytes = acc.body_bytes + byte_size(data)

        if body_bytes > max_body_bytes do
          {:halt, %{acc | too_large?: true}}
        else
          {:cont, %{acc | body: [data | acc.body], body_bytes: body_bytes}}
        end

      {:trailers, _headers}, acc ->
        {:cont, acc}
    end

    case Finch.stream_while(request, Hexpm.Finch, initial, stream, request_opts) do
      {:ok, %{too_large?: true}} ->
        {:error, :response_too_large}

      {:ok, response} ->
        {:ok,
         %Finch.Response{
           status: response.status,
           headers: response.headers,
           body: response.body |> Enum.reverse() |> IO.iodata_to_binary()
         }}

      {:error, reason, _response} ->
        {:error, reason}
    end
  end

  defp encode_params(body, _headers) when is_binary(body) or is_nil(body) do
    body
  end

  defp encode_params({:stream, _enumerable} = body, _headers), do: body

  defp encode_params(body, _headers) when is_list(body), do: body

  defp encode_params(body, headers) when is_map(body) do
    case List.keyfind(headers, "content-type", 0) do
      {_, "application/x-www-form-urlencoded"} -> URI.encode_query(body)
      {_, "application/json"} -> JSON.encode!(body)
      nil -> body
    end
  end

  defp decode_body(body, headers) do
    case List.keyfind(headers, "content-type", 0) do
      {_, "application/json" <> _} -> JSON.decode!(body)
      _ -> body
    end
  end

  defp read_response({:ok, %Finch.Response{status: status, headers: headers, body: body}}, true) do
    params = decode_body(body, headers)
    {:ok, status, headers, params}
  end

  defp read_response({:ok, %Finch.Response{status: status, headers: headers, body: body}}, false) do
    {:ok, status, headers, body}
  end

  defp read_response({:error, reason}, _decode_body?) do
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
