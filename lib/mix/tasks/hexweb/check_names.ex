defmodule Mix.Tasks.Hexweb.CheckNames do
  use Mix.Task
  require Logger

  @shortdoc "Check package names for typosquatters"

  def run(_args) do
    Mix.Task.run "app.start"

    threshold = Application.get_env(:hex_web, :levenshtein_threshold)

    threshold
    |> find_candidates
    |> HexWeb.Mailer.send_typosquat_candidates_email(threshold)

    :ok
  end

  def find_candidates(threshold) do
    query = """
    SELECT pnew.name new_name, pall.name curr_name, levenshtein(pall.name, pnew.name) as dist
    FROM packages as pall
    CROSS JOIN packages as pnew
    WHERE pall.name <> pnew.name
      AND pnew.inserted_at >= CURRENT_DATE
      AND levenshtein(pall.name, pnew.name) <= $1
    ORDER BY pall.name, dist;
    """

    Ecto.Adapters.SQL.query!(HexWeb.Repo, query, [threshold])
    |> Map.fetch!(:rows)
    |> Enum.uniq_by(fn([a, b, _]) -> if a > b, do: "#{a}-#{b}", else: "#{b}-#{a}" end)
  end
end
