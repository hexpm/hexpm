defmodule Hexpm.HTTP do
  require Logger

  @max_retry_times 3
  @base_sleep_time 100

  def get(url, headers, opts \\ []) do
    Finch.build(:get, url, headers, nil, opts)
    |> Finch.request(Hexpm.Finch)
    |> read_response()
  end

  def post(url, headers, body, opts \\ []) do
    Finch.build(:get, url, headers, body, opts)
    |> Finch.request(Hexpm.Finch)
    |> read_response()
  end

  def put(url, headers, body, opts \\ []) do
    Finch.build(:put, url, headers, body, opts)
    |> Finch.request(Hexpm.Finch)
    |> read_response()
  end

  def patch(url, headers, body, opts \\ []) do
    Finch.build(:patch, url, headers, body, opts)
    |> Finch.request(Hexpm.Finch)
    |> read_response()
  end

  def delete(url, headers, opts \\ []) do
    Finch.build(:delete, url, headers, nil, opts)
    |> Finch.request(Hexpm.Finch)
    |> read_response()
  end

  defp read_response({:ok, %Finch.Response{status: status, headers: headers, body: body}}) do
    {:ok, status, headers, body}
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
