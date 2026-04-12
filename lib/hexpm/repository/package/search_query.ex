defmodule Hexpm.Repository.Package.SearchQuery do
  @moduledoc """
  Parses and serializes hexpm package search strings into a structured form.

  Supports mixed free-text and `key:value` filter tokens. Unknown filter keys
  are preserved via the `:unknown` field so they round-trip through parse/serialize.
  """

  defstruct free_text: nil,
            depends: nil,
            build_tools: [],
            updated_after: nil,
            extra: [],
            name: nil,
            description: nil,
            unknown: []

  @type t :: %__MODULE__{}

  @known_keys ~w(name description depends build_tool updated_after extra)

  @spec parse(String.t() | nil) :: {:ok, t()} | {:error, term()}
  def parse(nil), do: {:ok, %__MODULE__{}}

  def parse(string) when is_binary(string) do
    string
    |> tokenize()
    |> Enum.reduce_while({:ok, %__MODULE__{}, []}, fn token, {:ok, acc, text} ->
      case apply_token(token, acc) do
        {:ok, acc} -> {:cont, {:ok, acc, text}}
        {:text, word} -> {:cont, {:ok, acc, [word | text]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, acc, text} ->
        free_text = text |> Enum.reverse() |> Enum.join(" ") |> nil_if_empty()

        {:ok,
         %{
           acc
           | free_text: free_text,
             extra: Enum.reverse(acc.extra),
             build_tools: Enum.reverse(acc.build_tools),
             unknown: Enum.reverse(acc.unknown)
         }}

      {:error, _} = err ->
        err
    end
  end

  defp nil_if_empty(""), do: nil
  defp nil_if_empty(s), do: s

  defp apply_token({:word, w}, _acc), do: {:text, w}

  defp apply_token({:pair, "name", v}, acc), do: {:ok, %{acc | name: v}}
  defp apply_token({:pair, "description", v}, acc), do: {:ok, %{acc | description: v}}
  defp apply_token({:pair, "depends", v}, acc), do: {:ok, %{acc | depends: v}}
  defp apply_token({:pair, "updated_after", v}, acc), do: {:ok, %{acc | updated_after: v}}

  defp apply_token({:pair, "build_tool", v}, acc) do
    {:ok, %{acc | build_tools: [v | acc.build_tools]}}
  end

  defp apply_token({:pair, "extra", v}, acc) do
    case String.split(v, ",", parts: 2) do
      [key, value] when key != "" -> {:ok, %{acc | extra: [{key, value} | acc.extra]}}
      _ -> {:error, {:extra, v}}
    end
  end

  defp apply_token({:pair, key, _v}, _acc) when key in @known_keys do
    raise "BUG: #{inspect(key)} is listed in @known_keys but has no apply_token clause"
  end

  defp apply_token({:pair, key, v}, acc) when key not in @known_keys do
    {:ok, %{acc | unknown: [{key, v} | acc.unknown]}}
  end

  # --- tokenizer ---

  defp tokenize(string) do
    string
    |> String.trim()
    |> do_tokenize([])
    |> Enum.reverse()
  end

  defp do_tokenize("", acc), do: acc

  defp do_tokenize(string, acc) do
    string = String.trim_leading(string)

    cond do
      string == "" ->
        acc

      (colon_index = colon_before_space(string)) != nil ->
        {key, rest} = String.split_at(string, colon_index)
        {:ok, value, rest_after} = read_value(String.slice(rest, 1..-1//1))
        do_tokenize(rest_after, [{:pair, key, value} | acc])

      true ->
        {word, rest} = read_word(string)
        do_tokenize(rest, [{:word, word} | acc])
    end
  end

  defp colon_before_space(string) do
    case :binary.match(string, ":") do
      {0, _} ->
        nil

      {colon, _} ->
        case Regex.run(~r/\s/, string, return: :index) do
          [{space, _}] when space < colon -> nil
          _ -> colon
        end

      :nomatch ->
        nil
    end
  end

  defp read_value(<<?", rest::binary>>) do
    case String.split(rest, "\"", parts: 2) do
      [value, tail] -> {:ok, value, String.trim_leading(tail)}
      [value] -> {:ok, value, ""}
    end
  end

  defp read_value(string) do
    {word, rest} = read_word(string)
    {:ok, word, rest}
  end

  defp read_word(string) do
    case String.split(string, ~r/\s+/, parts: 2) do
      [word] -> {word, ""}
      [word, tail] -> {word, String.trim_leading(tail)}
    end
  end

  @spec serialize(t()) :: String.t()
  def serialize(%__MODULE__{} = q) do
    [
      q.free_text,
      pair("name", q.name),
      pair("description", q.description),
      pair("depends", q.depends),
      Enum.map(q.build_tools, &pair("build_tool", &1)),
      pair("updated_after", q.updated_after),
      Enum.map(q.extra, fn {k, v} -> pair("extra", "#{k},#{v}") end),
      Enum.map(q.unknown, fn {k, v} -> pair(k, v) end)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp pair(_key, nil), do: nil
  defp pair(_key, ""), do: nil

  defp pair(key, value) do
    case String.replace(value, "\"", "") do
      "" ->
        nil

      stripped ->
        if String.contains?(stripped, " "),
          do: ~s(#{key}:"#{stripped}"),
          else: "#{key}:#{stripped}"
    end
  end
end
