defmodule Mix.Tasks.Hexweb.CheckNames do
  use Mix.Task
  require Logger

  @shortdoc "Check package names for typosquatters"

  def run(_args) do
    Mix.Task.run "app.start"

    threshold = Application.get_env(:hex_web, :levenshtein_threshold)

    threshold
    |> find_candidates
    |> send_mail(threshold)

    :ok
  end

  def find_candidates(threshold) do
    querystr = "SELECT pnew.name new_name, pall.name curr_name, levenshtein(pall.name, pnew.name) as dist
                FROM packages as pall
                CROSS JOIN packages as pnew
                WHERE pall.name <> pnew.name
                  AND pnew.inserted_at >= CURRENT_DATE
                  AND levenshtein(pall.name, pnew.name) <= $1
                ORDER BY pall.name, dist;"
    Ecto.Adapters.SQL.query!(HexWeb.Repo, querystr, [threshold])
    |> Map.fetch!(:rows)
    |> Enum.uniq_by(fn([a, b, _]) -> if a > b, do: "#{a}-#{b}", else: "#{b}-#{a}" end)
  end

  def send_mail(candidates, threshold) do
    HexWeb.Mailer.send(
      "typosquat_candidates.html",
      "Hex.pm - Typosquat candidates",
      [Application.get_env(:hex_web, :support_email)],
      candidates: candidates,
      threshold: threshold)
  end
end
