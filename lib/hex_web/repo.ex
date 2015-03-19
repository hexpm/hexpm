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
      Logger.info fn ->
        next = :os.timestamp()
        diff = :timer.now_diff(next, prev)

        {_, workers, _, _} = :poolboy.status(__MODULE__.Pool)

        [query_str(cmd), " (db_query=", inspect(div(diff, 100) / 10),
         "ms) (db_avail=", inspect(workers), ")"]
      end
    end
  end

  def log(_, fun) do
    fun.()
  end

  if Mix.env == :prod do
    defp query_str(cmd), do: :binary.replace(cmd, "\n", " ", [:global])
  else
    defp query_str(cmd), do: cmd
  end
end
