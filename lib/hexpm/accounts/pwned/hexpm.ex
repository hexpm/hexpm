defmodule Hexpm.Accounts.Pwned.Hexpm do
  @behaviour Hexpm.Accounts.Pwned

  @base_url "https://api.pwnedpasswords.com/"
  @weakness_threshold 1

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
    |> String.upcase()
  end

  defp range(searchable_range) do
    url = @base_url <> "range/#{searchable_range}"
    headers = [{"User-Agent", "hexpm"}]

    with {:ok, 200, _headers, ref} <- :hackney.get(url, headers, "", []),
         {:ok, body} <- :hackney.body(ref) do
      String.split(body, "\r\n")
    else
      []
    end
  end

  defp occurrences_of_hash(<<searchable_range::bytes-5, remainder::binary>>) do
    searchable_range
    |> range()
    |> Enum.find(fn data ->
      [hash | _t] = String.split(data, ":")
      hash == remainder
    end)
    |> number_of_occurrences()
  end

  defp number_of_occurrences(nil), do: 0

  defp number_of_occurrences(str) do
    [_hash, occurrences] = String.split(str, ":")

    case Integer.parse(occurrences) do
      {number, _extra} -> number
      _ -> 0
    end
  end
end
