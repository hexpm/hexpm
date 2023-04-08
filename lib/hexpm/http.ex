defmodule Hexpm.HTTP do
  require Logger

  @max_retry_times 3
  @base_sleep_time 100

  def get(url, headers, opts \\ []) do
    build_request(:get, url, headers, nil, opts)
    |> Finch.request(Hexpm.Finch)
    |> read_response()
  end

  def post(url, headers, body, opts \\ []) do
    build_request(:post, url, headers, body, opts)
    |> Finch.request(Hexpm.Finch)
    |> read_response()
  end

  def put(url, headers, body, opts \\ []) do
    build_request(:put, url, headers, body, opts)
    |> Finch.request(Hexpm.Finch)
    |> read_response()
  end

  def patch(url, headers, body, opts \\ []) do
    build_request(:patch, url, headers, body, opts)
    |> Finch.request(Hexpm.Finch)
    |> read_response()
  end

  def delete(url, headers, opts \\ []) do
    build_request(:delete, url, headers, nil, opts)
    |> Finch.request(Hexpm.Finch)
    |> read_response()
  end

  defp build_request(method, url, headers, body, opts) do
    params = encode_params(body, headers)
    Finch.build(method, url, headers, params, opts)
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
