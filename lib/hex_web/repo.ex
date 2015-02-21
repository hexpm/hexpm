defmodule HexWeb.Repo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres, env: Mix.env
  require Logger

  def conf(_env) do
    {url, opts} = Application.get_env(:hex_web, :database) |> Dict.pop(:url)
    parse_url(url) ++ opts
  end

  def priv,
    do: :code.priv_dir(:hex_web)

  def log({:query, cmd}, fun) do
    prev = :os.timestamp()

    try do
      fun.()
    after
      Logger.debug fn ->
        next = :os.timestamp()
        diff = :timer.now_diff(next, prev)
        {_, workers, _, _} = :poolboy.status(__MODULE__.Pool)
        [cmd, " (db_query=", inspect(div(diff, 100) / 10), "ms) (db_avail=", inspect(workers), ")"]
      end
    end
  end

  def log(_, fun) do
    fun.()
  end

  def query_apis do
    [Ecto.Query.API, HexWeb.Repo.API]
  end

  defmodule API do
    use Ecto.Query.Typespec

    deft integer
    deft string

    defs to_tsvector(string, string) :: string

    defs to_tsquery(string, string) :: string

    defs text_match(string, string) :: boolean

    defs json_access(string, string) :: string
    defs json_access(string, integer) :: string
  end
end
