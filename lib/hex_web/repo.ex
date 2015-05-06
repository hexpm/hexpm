defmodule HexWeb.Repo do
  use Ecto.Repo, otp_app: :hex_web
  require Logger

  def priv,
    do: :code.priv_dir(:hex_web)

  def log({:query, cmd, params}, fun) do
    prev = :os.timestamp()

    try do
      fun.()
    after
      Logger.info fn ->
        next = :os.timestamp()
        diff = :timer.now_diff(next, prev)

        data = Enum.map(params, fn
          %Ecto.Query.Tagged{value: value} -> value
          value -> value
        end)

        [cmd, " ", inspect(data), " (db_query=", inspect(div(diff, 100) / 10), "ms)"]
      end
    end
  end

  def log(_, fun) do
    fun.()
  end
end
