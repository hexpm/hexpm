defmodule HexpmWeb.DiffController do
  use HexpmWeb, :controller

  def index(conn, params) do
    render(
      conn,
      "index.html",
      title: "Package Diffs",
      container: "flex-1 flex flex-col",
      diffs: comparisons(params)
    )
  end

  def comparisons(params) do
    params
    |> Map.get("diffs", Map.get(params, "diff", []))
    |> List.wrap()
    |> Enum.flat_map(&parse_comparison/1)
  end

  defp parse_comparison(comparison) when is_binary(comparison) do
    case String.split(comparison, ":", parts: 3) do
      [package, from, to] when package != "" and from != "" and to != "" ->
        [{package, from, to}]

      _other ->
        []
    end
  end

  defp parse_comparison(_comparison), do: []
end
