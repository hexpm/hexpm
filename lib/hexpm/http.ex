defmodule Hexpm.HTTP do
  require Logger

  @max_retry_times 3
  @base_sleep_time 100

  def get(url, headers) do
    :hackney.get(url, headers)
    |> read_response()
  end

  def put(url, headers, body) do
    :hackney.put(url, headers, body)
    |> read_response()
  end

  def delete(url, headers) do
    :hackney.delete(url, headers)
    |> read_response()
  end

  defp read_response(result) do
    with {:ok, status, headers, ref} <- result,
         {:ok, body} <- :hackney.body(ref) do
      {:ok, status, headers, body}
    end
  end

  def retry(fun, name) do
    retry(fun, name, 0)
  end

  defp retry(fun, name, times) do
    case fun.() do
      {:error, reason} ->
        Logger.warn("#{name} API ERROR: #{inspect(reason)}")

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
