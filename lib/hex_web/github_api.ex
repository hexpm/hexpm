defmodule HexWeb.GithubApi do
  use HTTPoison.Base

  def start_link do
    args = [ttl:       :timer.hours(24),
            ttl_check: :timer.hours(4)]

    ConCache.start_link args, name: __MODULE__
  end

  defp find_package_name(title), do: String.replace(title, ~r/(Add Package )|"/, "")

  defp build_path(list), do: Enum.join(list, "/")
  defp build_params(list) do
    list |> Enum.map(fn({k, v}) -> "#{k}=#{v}" end)
         |> Enum.join("&")
  end

  @doc false
  def process_url(url), do: "https://api.github.com" <> url
  @doc false
  def process_response_body(body), do: Poison.decode!(body)

  @doc """
  Send a GET request and return its JSON response.
  """
  @spec read([String], Keyword) :: term
  def read(path, params) do
    url = "/" <> build_path(path) <> "?" <> build_params(params)
    get!(url).body
  end

  @doc """
  Get the last closed issues of a repository.
  """
  @spec read(String, Integer) :: [term]
  def last_closed_issues(repo, count) do
    read ["repos", repo, "issues"],
      state:    :closed,
      sort:     :updated,
      per_page: count
  end

  @doc """
  Get the last added packages to an awesome-elixir list.
  """
  def last_awesome_packages(repo, count) do
    ConCache.get_or_store __MODULE__, repo, fn ->
      last_closed_issues(repo, count) |> Enum.filter_map(
          fn(x) -> !x["pull_request"] end,
          fn(x) -> find_package_name(x["title"]) end)
    end
  end
end

