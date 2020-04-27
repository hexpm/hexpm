defmodule Hexpm.ShortURLs.ShortURL do
  use Hexpm.Schema
  alias Hexpm.ShortURLs
  alias Hexpm.ShortURLs.ShortURL

  schema "short_urls" do
    field :url, :string
    field :short_code, :string

    timestamps()
  end

  def changeset(params) do
    %ShortURL{}
    |> cast(params, [:url])
    |> validate_required([:url])
    |> put_change(:short_code, generate_random(5))
    |> validate_required(:short_code, message: "Could not generate a unique short code")
    |> unique_constraint(:short_code)
  end

  defp charset do
    capitals = Enum.map(?A..?Z, fn ch -> <<ch>> end)
    lowers = Enum.map(?a..?z, fn ch -> <<ch>> end)
    numbers = Enum.map(?0..?9, fn ch -> <<ch>> end)
    ambiguous = ["I", "0", "O", "l"]
    (capitals ++ lowers ++ numbers) -- ambiguous
  end

  defp generate_random(length, retries \\ 5)
  defp generate_random(_length, 0), do: nil

  defp generate_random(length, retries) do
    short_code = Enum.reduce(1..length, "", fn _x, acc -> acc <> Enum.random(charset()) end)
    # Make sure this short_code is unique before continuing
    if short_code_unique?(short_code), do: short_code, else: generate_random(length, retries - 1)
  end

  defp short_code_unique?(short_code) do
    short_code |> ShortURLs.get_by_short_code() |> is_nil()
  end
end
