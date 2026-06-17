defmodule Hexpm.Repository.Cooldown do
  @moduledoc """
  Parses cooldown duration strings (e.g. `"14d"`, `"2w"`, `"1mo"`).

  Mirrors `Hex.Cooldown.duration_to_seconds/1` on the client so that a
  string accepted here resolves to the same number of seconds in the
  CLI.
  """

  @doc """
  Returns `{:ok, seconds}` for a recognized duration string and
  `:error` otherwise.
  """
  @spec duration_to_seconds(String.t()) :: {:ok, non_neg_integer()} | :error
  def duration_to_seconds("0"), do: {:ok, 0}

  def duration_to_seconds(string) when is_binary(string) do
    with [_, digits, unit] <- Regex.run(~r/\A(\d+)(d|w|mo)\z/, string),
         {n, ""} <- Integer.parse(digits) do
      {:ok, n * unit_seconds(unit)}
    else
      _ -> :error
    end
  end

  def duration_to_seconds(_), do: :error

  defp unit_seconds("d"), do: 86_400
  defp unit_seconds("w"), do: 86_400 * 7
  defp unit_seconds("mo"), do: 86_400 * 30
end
