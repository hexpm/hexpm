defmodule HexWeb.GithubApi do
  use HTTPoison.Base

  defp build_path([hd]) do
    to_string(hd)
  end
  defp build_path([hd|tl]) do
    "#{hd}/#{build_path(tl)}"
  end

  defp build_params([]) do
    ""
  end
  defp build_params([{k, v}]) do
    "#{k}=#{v}"
  end
  defp build_params([{k, v}|tl]) do
    "#{k}=#{v}&#{build_params(tl)}"
  end

  def read(path, params) do
    url = "/" <> build_path(path) <> "?" <> build_params(params)
    get!(url).body
  end

  def process_url(url) do
    "https://api.github.com" <> url
  end

  def process_response_body(body) do
    body |> Poison.decode!
         # |> Enum.map(fn {k,v} -> {:"#{k}", v} end)
  end

  def last_closed_issues(repo, count) do
    read ["repos", repo, "issues"],
      state:    :closed,
      sort:     :updated,
      per_page: count
  end

  defp find_package_name(title) do
    title
      |> String.replace(~r/(Add Package )|"/, "")
  end

  def last_awesome_packages(repo, count) do
    last_closed_issues(repo, count)
      |> Enum.filter_map(fn(x) -> !x["pull_request"] end,
                         fn(x) -> find_package_name(x["title"]) end)
  end

end
