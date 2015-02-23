defmodule HexWeb.GithubApi do
  require Logger
  use HTTPoison.Base

  def start_link do
    args = [ttl:       :timer.hours(Application.get_env(:hex_web, :gh_resp_ttl)),
            ttl_check: :timer.hours(Application.get_env(:hex_web, :gh_resp_ttlc))]

    ConCache.start_link args, name: __MODULE__
  end

  defp find_package_name(title), do: String.replace(title, ~r/(Add Package )|"/, "")

  defp build_path(list), do: Enum.join(list, "/")
  defp build_params(list) do
    list |> Enum.map(fn({k, v}) -> "#{k}=#{v}" end)
         |> Enum.join("&")
  end

  @doc false
  def process_url(url) do
    tmp = "https://api.github.com" <> url
    Logger.info "Retrieving data from Github"
    Logger.debug "Github HTTP #{url}"
    tmp
  end
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
  @spec last_closed_issues(String, Integer) :: [term]
  def last_closed_issues(repo, count) do
    read ["repos", repo, "issues"],
      state:    :closed,
      sort:     :updated,
      per_page: count,
      labels:   "help%20wanted" # filter out pull-requests
  end

  @doc """
  Get the last added packages to an awesome-elixir list.
  """
  @spec last_awesome_packages(String, Integer) :: [String]
  def last_awesome_packages(repo, count) do
    ConCache.get_or_store __MODULE__, repo, fn ->
      last_closed_issues(repo, count) |> Enum.filter_map(
          fn(x) -> !x["pull_request"] end,
          fn(x) -> find_package_name(x["title"]) end)
    end
  end
end

