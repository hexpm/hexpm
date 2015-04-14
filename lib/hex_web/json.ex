defmodule HexWeb.JSON do
  @behaviour Ecto.Type

  def type, do: :json

  def blank?(""),  do: true
  def blank?(nil), do: true
  def blank?(_),   do: false

  def cast(term)
      when is_map(term)
        or is_binary(term)
        or is_list(term)
        or is_number(term) do
    {:ok, term}
  end

  def cast(_) do
    :error
  end

  def load(string) do
    case Poison.decode(string) do
      {:ok, term} -> {:ok, term}
      {:error, _} -> :error
    end
  end

  def dump(term) do
    case Poison.encode(term) do
      {:ok, string} -> {:ok, string}
      {:error, _}   -> :error
    end
  end
end
