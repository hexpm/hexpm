defmodule HexpmWeb.DiffRedirectController do
  use HexpmWeb, :controller

  def index(conn, params), do: redirect_comparison_or_packages(conn, params)

  def show(conn, %{"package" => package, "versions" => versions}) do
    permanent_redirect(conn, ~p"/diff/#{package}/#{versions}")
  end

  def path(conn, _params), do: permanent_redirect(conn, "/packages", "")

  defp redirect_comparison_or_packages(conn, params) do
    case first_comparison(params) do
      {package, from, to} ->
        query_string =
          params
          |> Map.drop(["diff", "diffs"])
          |> URI.encode_query()

        permanent_redirect(conn, ~p"/diff/#{package}/#{from <> ".." <> to}", query_string)

      nil ->
        permanent_redirect(conn, "/packages", "")
    end
  end

  defp first_comparison(params) do
    params
    |> Map.get("diffs", Map.get(params, "diff", []))
    |> List.wrap()
    |> Enum.find_value(&parse_comparison/1)
  end

  defp parse_comparison(comparison) when is_binary(comparison) do
    case String.split(comparison, ":", parts: 3) do
      [package, from, to] when package != "" and from != "" and to != "" ->
        {package, from, to}

      _other ->
        nil
    end
  end

  defp parse_comparison(_comparison), do: nil
end
