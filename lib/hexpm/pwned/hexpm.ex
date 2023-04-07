defmodule Hexpm.Pwned.HaveIBeenPwned do
  alias Hexpm.HTTP
  require Logger

  @behaviour Hexpm.Pwned

  @base_url "https://api.pwnedpasswords.com/"
  @weakness_threshold 1
  @timeout 500

  @spec password_breached?(String.t()) :: boolean
  def password_breached?(string_password) do
    string_password
    |> hash_password()
    |> occurrences_of_hash()
    |> Kernel.>=(@weakness_threshold)
  end

  defp hash_password(string_password) do
    :sha
    |> :crypto.hash(string_password)
    |> Base.encode16()
  end

  defp range(searchable_range) do
    url = @base_url <> "range/#{searchable_range}"
    headers = [{"user-agent", "hexpm"}]
    opts = [pool_timeout: @timeout, receive_timeout: @timeout]

    case HTTP.retry(fn -> HTTP.get(url, headers, opts) end, "pwned") do
      {:ok, 200, _headers, body} ->
        String.split(body, "\r\n")

      {:error, reason} ->
        Logger.error("pwned request failed: #{inspect(reason)}")
        []
    end
  end

  defp occurrences_of_hash(<<searchable_range::bytes-5, remainder::binary>>) do
    searchable_range
    |> range()
    |> Enum.map(&String.split(&1, ":"))
    |> Enum.find_value("0", fn
      [^remainder, occurrences] -> occurrences
      _ -> nil
    end)
    |> String.to_integer()
  end
end
