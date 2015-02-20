defmodule HexWeb.Repo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres, env: Mix.env

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

  # def log(action, fun) do
  #   IO.inspect action
  #   fun.()
  # end

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
