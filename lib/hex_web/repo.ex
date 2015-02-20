defmodule HexWeb.Repo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres, env: Mix.env
  require Logger

  def conf(env) do
    case env do
      :prod ->
        parse_url(Application.get_env(:hex_web, :database_url)) ++ [lazy: false, size: "30", max_overflow: "0"]
      :dev ->
        parse_url Application.get_env(:hex_web, :database_url)
      :test ->
        parse_url(Application.get_env(:hex_web, :database_url)) ++ [size: "1", max_overflow: "0"]
    end
  end

  def priv,
    do: :code.priv_dir(:hex_web)

  def log({:query, cmd}, fun) do
    prev = :os.timestamp()

    try do
      fun.()
    after
      Logger.info fn ->
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
