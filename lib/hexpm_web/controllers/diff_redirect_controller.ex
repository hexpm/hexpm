defmodule HexpmWeb.DiffRedirectController do
  use HexpmWeb, :controller

  alias HexpmWeb.DiffController

  def index(conn, params) do
    case DiffController.comparisons(params) do
      [] ->
        permanent_redirect(conn, "/packages", "")

      [{package, from, to}] ->
        permanent_redirect(conn, ~p"/diff/#{package}/#{from <> ".." <> to}", extra_query(params))

      comparisons ->
        query =
          comparisons
          |> Enum.map(fn {package, from, to} -> {"diffs[]", "#{package}:#{from}:#{to}"} end)
          |> URI.encode_query()

        permanent_redirect(conn, ~p"/diffs", join_query(query, extra_query(params)))
    end
  end

  def show(conn, %{"package" => package, "versions" => versions}) do
    permanent_redirect(conn, ~p"/diff/#{package}/#{versions}")
  end

  def path(conn, _params), do: permanent_redirect(conn, "/packages", "")

  defp extra_query(params) do
    params
    |> Map.drop(["diff", "diffs"])
    |> URI.encode_query()
  end

  defp join_query(query, ""), do: query
  defp join_query(query, extra), do: query <> "&" <> extra
end
